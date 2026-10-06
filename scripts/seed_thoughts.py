"""
seed_thoughts.py

Seeds Same Here's `thoughts` and `options` tables in Supabase from AI-generated
JSON files (see docs/supabase-integration.md for the generation prompt).

Usage:
    python seed_thoughts.py path/to/tecnologia.json [more_files.json ...]
    python seed_thoughts.py path/to/seed_data/            # seeds every *.json in the folder
    python seed_thoughts.py --dry-run seed_data/          # report what would be inserted, write nothing

    python seed_thoughts.py --skip-link-check seed_data/  # don't hit the network for links

Safe to re-run: a question is skipped if an AI-generated thought with the same
topic and text already exists (compared ignoring case and extra spaces), and
repeats inside the files themselves are only inserted once.

Every question must have a `link`, and the link must actually load (HTTP status
below 400 after redirects) — AI models sometimes invent plausible-looking URLs
that 404. Questions whose link is missing, malformed or broken are skipped and
reported. The check runs in --dry-run too, so you can vet a file before seeding.

Setup:
    pip install -r requirements.txt
    cp .env.example .env   # then fill in your project's values

Env vars (scripts/.env, never commit real keys):
    SUPABASE_URL               e.g. https://xxxx.supabase.co
    SUPABASE_SERVICE_ROLE_KEY  the *service role* key (bypasses RLS) — local/CI use only,
                                never ship this key inside the iOS app.

Expected JSON shape (one file per topic, array of question objects — this is
exactly what the "Same Here" AI prompt produces):
[
  {
    "text": "...",
    "tag": "Tecnologia",
    "link": "https://...",
    "options": [
      {"title": "Android", "votes": 1234},
      {"title": "iOS", "votes": 987}
    ]
  },
  ...
]
"""

import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Callable, Optional
from urllib.parse import quote, urlsplit, urlunsplit

from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

REQUIRED_QUESTION_KEYS = {"text", "tag", "link", "options"}
REQUIRED_OPTION_KEYS = {"title", "votes"}

PAGE_SIZE = 1000  # PostgREST caps a single select at 1000 rows by default

QuestionKey = tuple[str, str]

# Returns None when the link is fine, or a short reason why it isn't.
LinkChecker = Callable[[str], Optional[str]]

LINK_TIMEOUT_SECONDS = 10
# Wikipedia (and many sites) reject requests without a descriptive User-Agent.
LINK_USER_AGENT = "SameHereSeedScript/1.0 (link check for seeded questions)"


def to_ascii_url(url: str) -> str:
    """Percent-encode non-ASCII characters (e.g. Wikipedia's 'Tecnología') so
    urllib can request the URL. Already-encoded '%xx' sequences are kept."""
    parts = urlsplit(url)
    safe = "/%:@!$&'()*+,;=-._~"
    return urlunsplit((
        parts.scheme,
        parts.netloc.encode("idna").decode("ascii"),
        quote(parts.path, safe=safe),
        quote(parts.query, safe=safe + "?"),
        quote(parts.fragment, safe=safe),
    ))


def make_ssl_context() -> ssl.SSLContext:
    """Prefer certifi's CA bundle. The python.org installer on macOS ships
    without system certificates until 'Install Certificates.command' is run,
    which makes every HTTPS request fail with CERTIFICATE_VERIFY_FAILED.
    certifi is already installed as a dependency of the supabase package."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


SSL_HELP = (
    "\nCould not verify HTTPS certificates, so no link can be checked.\n"
    "This is a problem with this Python installation, not with the links. Fix it with:\n"
    "    python3 -m pip install --upgrade certifi\n"
    "or, for the python.org installer on macOS, run once:\n"
    '    open "/Applications/Python {major}.{minor}/Install Certificates.command"\n'
    "Or skip the network check for now with --skip-link-check."
)


def make_http_link_checker() -> LinkChecker:
    cache: dict[str, Optional[str]] = {}
    context = make_ssl_context()

    def request_status(url: str, method: str) -> int:
        req = urllib.request.Request(
            url, method=method, headers={"User-Agent": LINK_USER_AGENT}
        )
        try:
            with urllib.request.urlopen(
                req, timeout=LINK_TIMEOUT_SECONDS, context=context
            ) as resp:
                return resp.status
        except urllib.error.HTTPError as err:
            return err.code

    def check(link: str) -> Optional[str]:
        if link in cache:
            return cache[link]
        try:
            url = to_ascii_url(link)
            status = request_status(url, "HEAD")
            if status in (403, 405, 501):  # some servers refuse HEAD; retry with GET
                status = request_status(url, "GET")
            reason = None if status < 400 else f"HTTP {status}"
        except Exception as exc:  # DNS failure, timeout, TLS error, bad URL...
            if isinstance(getattr(exc, "reason", exc), ssl.SSLCertVerificationError):
                # An environment problem: every link would fail the same way,
                # so stop instead of skipping the whole file.
                sys.exit(SSL_HELP.format(
                    major=sys.version_info.major, minor=sys.version_info.minor
                ))
            reason = f"unreachable ({exc.__class__.__name__}: {exc})"
        cache[link] = reason
        return reason

    return check


# AI chat UIs often hand links back as markdown: "[url](url)" or "<url>".
_MARKDOWN_LINK = re.compile(r"^\[[^\]]*\]\((?P<url>.+)\)$")


def clean_link(link: object) -> object:
    """Unwrap a markdown link or <angle brackets> to the bare URL.
    Greedy on purpose so URLs with parentheses, like
    .../wiki/Parche_(informática), survive."""
    if not isinstance(link, str):
        return link
    link = link.strip()
    match = _MARKDOWN_LINK.match(link)
    if match:
        link = match.group("url").strip()
    if link.startswith("<") and link.endswith(">"):
        link = link[1:-1].strip()
    return link


def link_format_problem(link: object) -> Optional[str]:
    if not isinstance(link, str) or not link.strip():
        return "link is empty"
    parts = urlsplit(link.strip())
    if parts.scheme not in ("http", "https") or not parts.netloc:
        return f"link is not an http(s) URL: {link!r}"
    return None


def normalize(text: str) -> str:
    """Case- and whitespace-insensitive form used to spot duplicates."""
    return " ".join(text.split()).casefold()


def question_key(topic: str, message: str) -> QuestionKey:
    return (normalize(topic), normalize(message))


def load_existing_keys(client: Client) -> set[QuestionKey]:
    """Every AI-generated thought already in the database, as duplicate keys."""
    keys: set[QuestionKey] = set()
    start = 0
    while True:
        res = (
            client.table("thoughts")
            .select("topic, message")
            .eq("is_ai_generated", True)
            .order("id")
            .range(start, start + PAGE_SIZE - 1)
            .execute()
        )
        rows = res.data or []
        keys.update(question_key(r["topic"], r["message"]) for r in rows)
        if len(rows) < PAGE_SIZE:
            return keys
        start += PAGE_SIZE


def get_client() -> Client:
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        sys.exit(
            "Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.\n"
            "Copy scripts/.env.example to scripts/.env and fill in your project's values "
            "(Supabase dashboard > Project Settings > API)."
        )
    return create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def collect_json_files(paths: list[str]) -> list[Path]:
    files: list[Path] = []
    for raw in paths:
        p = Path(raw)
        if p.is_dir():
            files.extend(sorted(p.glob("*.json")))
        elif p.is_file():
            files.append(p)
        else:
            print(f"  skip (not found): {raw}")
    return files


def validate_question(q: dict, source_file: str, index: int) -> bool:
    missing = REQUIRED_QUESTION_KEYS - q.keys()
    if missing:
        print(f"  skip [{source_file} #{index}]: missing fields {missing}")
        return False
    options = q.get("options") or []
    if not (2 <= len(options) <= 6):
        print(f"  skip [{source_file} #{index}]: needs 2-6 options, got {len(options)}")
        return False
    for opt in options:
        if REQUIRED_OPTION_KEYS - opt.keys():
            print(f"  skip [{source_file} #{index}]: an option is missing title/votes")
            return False
    q["link"] = clean_link(q.get("link"))
    problem = link_format_problem(q["link"])
    if problem:
        print(f"  skip [{source_file} #{index}]: {problem}")
        return False
    return True


def seed_file(
    client: Client,
    path: Path,
    seen: set[QuestionKey],
    dry_run: bool = False,
    check_link: Optional[LinkChecker] = None,
) -> tuple[int, int, int]:
    """Returns (inserted, duplicates, skipped). `seen` is updated in place.
    `check_link` is None to skip the network check on links."""
    with open(path, encoding="utf-8") as f:
        questions = json.load(f)

    inserted, duplicates, skipped = 0, 0, 0
    for i, q in enumerate(questions):
        if not validate_question(q, path.name, i):
            skipped += 1
            continue

        key = question_key(q["tag"], q["text"])
        if key in seen:
            duplicates += 1
            continue

        link = q["link"].strip()
        if check_link is not None:
            problem = check_link(link)
            if problem:
                print(f"  skip [{path.name} #{i}]: broken link {link} — {problem}")
                skipped += 1
                continue

        if dry_run:
            seen.add(key)
            inserted += 1
            continue

        thought_row = {
            "message": q["text"].strip(),
            "topic": q["tag"].strip(),
            "source_link": link,
            "is_ai_generated": True,
            "author_id": None,
        }

        thought_id = None
        try:
            thought_res = client.table("thoughts").insert(thought_row).execute()
            thought_id = thought_res.data[0]["id"]

            option_rows = [
                {
                    "thought_id": thought_id,
                    "title": opt["title"].strip(),
                    "seed_votes": int(opt["votes"]),
                    "position": pos,
                }
                for pos, opt in enumerate(q["options"])
            ]
            client.table("options").insert(option_rows).execute()
            seen.add(key)
            inserted += 1
        except Exception as exc:  # keep seeding the rest even if one row fails
            print(f"  error [{path.name} #{i}]: {exc}")
            skipped += 1
            if thought_id is not None:
                # Don't leave a question with no options behind; its options
                # (if any made it) go with it via ON DELETE CASCADE.
                try:
                    client.table("thoughts").delete().eq("id", thought_id).execute()
                except Exception as cleanup_exc:
                    print(f"  could not remove half-inserted thought {thought_id}: {cleanup_exc}")

    return inserted, duplicates, skipped


def main() -> None:
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    skip_link_check = "--skip-link-check" in args
    args = [a for a in args if a not in ("--dry-run", "--skip-link-check")]
    if not args:
        sys.exit(
            "Usage: python seed_thoughts.py [--dry-run] [--skip-link-check] "
            "<file_or_folder.json> [...]"
        )

    files = collect_json_files(args)
    if not files:
        sys.exit("No JSON files found.")

    client = get_client()
    seen = load_existing_keys(client)
    print(f"{len(seen)} AI-generated thoughts already in the database.")
    if dry_run:
        print("Dry run: nothing will be written.")
    check_link = None if skip_link_check else make_http_link_checker()
    if skip_link_check:
        print("Link check disabled: links are only checked for format.")
    print()

    verb = "would be inserted" if dry_run else "inserted"
    total_inserted, total_dupes, total_skipped = 0, 0, 0
    for path in files:
        print(f"Seeding {path} ...")
        inserted, dupes, skipped = seed_file(client, path, seen, dry_run, check_link)
        total_inserted += inserted
        total_dupes += dupes
        total_skipped += skipped
        print(f"  -> {inserted} {verb}, {dupes} already existed, {skipped} skipped")

    print(
        f"\nDone. {total_inserted} thoughts {verb}, "
        f"{total_dupes} already existed, {total_skipped} skipped."
    )


if __name__ == "__main__":
    main()
