// Same Here — send-digest
//
// Sends the "new questions" push to every device that opted into the given
// frequency. Called by pg_cron (see supabase/push_schedule.sql) with
//   POST { "frequency": "weekly" | "daily" }   header x-cron-secret: <secret>
//
// Deploy:   supabase functions deploy send-digest --no-verify-jwt --project-ref <ref>
// Secrets:  supabase secrets set --project-ref <ref> \
//             APNS_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)" APNS_KEY_ID=XXXXXXXXXX \
//             APNS_TEAM_ID=KV62XM9X65 APNS_BUNDLE_ID=bennyreyes.dev.SameHere \
//             DIGEST_CRON_SECRET=<same secret as in Vault>
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
//
// JWT verification is off (--no-verify-jwt) because the caller is pg_cron, not
// a user; the shared secret is what keeps everyone else out.

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

type Frequency = "daily" | "weekly";
type Locale = "es" | "en";

interface DeviceRow {
  token: string;
  environment: "sandbox" | "production";
  locale: Locale;
}

interface TopicCount {
  topic: string;
  total: number;
}

const TOPIC_NAMES: Record<string, Record<Locale, string>> = {
  GENERAL: { es: "General", en: "General" },
  TECNOLOGIA: { es: "Tecnología", en: "Technology" },
  ENTRETENIMIENTO: { es: "Entretenimiento", en: "Entertainment" },
  DEPORTES: { es: "Deportes", en: "Sports" },
  COMIDA: { es: "Comida", en: "Food" },
  VIAJES: { es: "Viajes", en: "Travel" },
  RELACIONES: { es: "Relaciones", en: "Relationships" },
  TRABAJO: { es: "Trabajo", en: "Work" },
};

const PAGE_SIZE = 1000;
const CONCURRENCY = 20;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const secret = Deno.env.get("DIGEST_CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "Unauthorized" }, 401);
  }

  let frequency: Frequency;
  try {
    const body = await req.json();
    if (body?.frequency !== "daily" && body?.frequency !== "weekly") throw new Error();
    frequency = body.frequency;
  } catch {
    return json({ error: 'Body must be {"frequency":"daily"|"weekly"}' }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // 1. What's new in the period. Nothing new → nobody gets a push.
  const days = frequency === "daily" ? 1 : 7;
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const { data: counts, error: countError } = await supabase
    .rpc("new_thoughts_by_topic", { since });
  if (countError) return json({ error: countError.message }, 500);

  const topics = (counts ?? []) as TopicCount[];
  const totalNew = topics.reduce((sum, t) => sum + Number(t.total), 0);
  if (totalNew === 0) return json({ frequency, newThoughts: 0, sent: 0 });

  // 2. One APNs token (JWT) for the whole run; valid for up to an hour.
  const jwt = await apnsJWT();
  const bundleID = Deno.env.get("APNS_BUNDLE_ID")!;
  const messages: Record<Locale, { title: string; body: string }> = {
    es: digestMessage(topics, totalNew, frequency, "es"),
    en: digestMessage(topics, totalNew, frequency, "en"),
  };

  // 3. Every opted-in device, page by page.
  let sent = 0;
  let failed = 0;
  const deadTokens: string[] = [];

  for (let from = 0; ; from += PAGE_SIZE) {
    const { data: rows, error } = await supabase
      .from("device_tokens")
      .select("token, environment, locale")
      .eq("frequency", frequency)
      .order("token")
      .range(from, from + PAGE_SIZE - 1);
    if (error) return json({ error: error.message }, 500);

    const devices = (rows ?? []) as DeviceRow[];
    for (let i = 0; i < devices.length; i += CONCURRENCY) {
      const batch = devices.slice(i, i + CONCURRENCY);
      const results = await Promise.all(batch.map((device) =>
        sendPush(device, messages[device.locale] ?? messages.es, topics[0].topic, jwt, bundleID)
      ));
      results.forEach((result, index) => {
        if (result === "sent") sent++;
        else {
          failed++;
          if (result === "dead") deadTokens.push(batch[index].token);
        }
      });
    }
    if (devices.length < PAGE_SIZE) break;
  }

  // 4. Tokens APNs says are gone (app deleted, etc.).
  if (deadTokens.length > 0) {
    await supabase.from("device_tokens").delete().in("token", deadTokens);
  }

  return json({ frequency, newThoughts: totalNew, sent, failed, removed: deadTokens.length });
});

/// "12 preguntas nuevas de Tecnología" when one topic is most of it,
/// otherwise the top two topics and how many more.
function digestMessage(
  topics: TopicCount[],
  totalNew: number,
  frequency: Frequency,
  locale: Locale,
): { title: string; body: string } {
  const name = (topic: string) => TOPIC_NAMES[topic]?.[locale] ?? topic;
  const [first, second] = topics;
  const firstCount = Number(first.total);

  if (locale === "es") {
    const when = frequency === "daily" ? "Hoy" : "Esta semana";
    const title = "Preguntas nuevas en Same Here";
    if (topics.length === 1 || firstCount / totalNew >= 0.7) {
      return { title, body: `${when} agregamos ${plural(firstCount, "pregunta", "preguntas")} de ${name(first.topic)}. ¿Piensas lo mismo que los demás?` };
    }
    const rest = totalNew - firstCount - Number(second.total);
    const tail = rest > 0 ? ` y ${rest} más` : "";
    return { title, body: `${when} agregamos ${firstCount} de ${name(first.topic)}, ${second.total} de ${name(second.topic)}${tail}. ¡Ven a votar!` };
  }

  const when = frequency === "daily" ? "today" : "this week";
  const title = "New questions on Same Here";
  if (topics.length === 1 || firstCount / totalNew >= 0.7) {
    return { title, body: `${plural(firstCount, "new question", "new questions")} about ${name(first.topic)} ${when}. Are you the only one?` };
  }
  const rest = totalNew - firstCount - Number(second.total);
  const tail = rest > 0 ? ` and ${rest} more` : "";
  return { title, body: `New ${when}: ${firstCount} about ${name(first.topic)}, ${second.total} about ${name(second.topic)}${tail}. Come vote!` };
}

function plural(count: number, one: string, many: string): string {
  return `${count} ${count === 1 ? one : many}`;
}

type SendResult = "sent" | "dead" | "error";

async function sendPush(
  device: DeviceRow,
  message: { title: string; body: string },
  topic: string,
  jwt: string,
  bundleID: string,
): Promise<SendResult> {
  const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  try {
    const response = await fetch(`https://${host}/3/device/${device.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleID,
        "apns-push-type": "alert",
        // 5 = deliver when convenient for the device; right for a digest.
        "apns-priority": "5",
        // Not worth delivering a day late.
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 24 * 60 * 60),
        "apns-collapse-id": "digest",
      },
      body: JSON.stringify({
        aps: { alert: message, sound: "default" },
        // For the app: which topic to open when the push is tapped.
        topic,
      }),
    });
    if (response.ok) return "sent";

    const reason = (await response.json().catch(() => ({})))?.reason ?? "";
    console.warn(`APNs ${response.status} ${reason} for …${device.token.slice(-6)}`);
    if (response.status === 410 || reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic") {
      return "dead";
    }
    return "error";
  } catch (error) {
    console.error(`APNs request failed: ${error}`);
    return "error";
  }
}

async function apnsJWT(): Promise<string> {
  const key = await importPKCS8(Deno.env.get("APNS_KEY_P8")!, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID")! })
    .setIssuer(Deno.env.get("APNS_TEAM_ID")!)
    .setIssuedAt()
    .sign(key);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
