import SwiftUI

struct AppCard: Identifiable {
    let id = UUID().uuidString
    let title: String
    let subtitle: String
    let category: String
    let color: Color
}

struct AppStoreExpansionView: View {
    @Namespace private var animation
    @State private var selectedApp: AppCard? = nil
    
    let apps = [
        AppCard(title: "Genshin Impact", subtitle: "Explora Teyvat hoy", category: "JUEGO DEL DÍA", color: .blue),
        AppCard(title: "Procreate Pocket", subtitle: "Ilustración digital", category: "IMPRESCINDIBLE", color: .purple),
        AppCard(title: "Fitness+", subtitle: "Entrena en cualquier lugar", category: "SALUD", color: .orange)
    ]
    
    var body: some View {
        ZStack {
            // MARK: - Lista Principal
            ScrollView {
                VStack(spacing: 25) {
                    Text("Hoy")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    ForEach(apps) { app in
                        CardView(app: app)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    selectedApp = app
                                }
                            }
                    }
                }
                .padding(.vertical)
            }
            .opacity(selectedApp == nil ? 1 : 0) // Oculta el fondo para evitar parpadeos
            
            // MARK: - Vista Detalle Pantalla Completa
            if let app = selectedApp {
                DetailView(app: app)
                    .ignoresSafeArea()
            }
        }
    }
    
    // MARK: - Tarjeta en la Lista
    @ViewBuilder
    func CardView(app: AppCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.category)
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.8))
            
            Text(app.title)
                .font(.title.bold())
                .foregroundColor(.white)
            
            Spacer()
            
            Text(app.subtitle)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .background(
            // Banner animado
            RoundedRectangle(cornerRadius: 20)
                .fill(app.color)
                .matchedGeometryEffect(id: "background_\(app.id)", in: animation)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Vista Detalle
    @ViewBuilder
    func DetailView(app: AppCard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                // Banner expandido
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                selectedApp = nil
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    Text(app.category)
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(app.title)
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text(app.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(20)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
                .frame(height: 450)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(app.color)
                        .matchedGeometryEffect(id: "background_\(app.id)", in: animation)
                )
                
                // Contenido del detalle
                VStack(alignment: .leading, spacing: 16) {
                    Text("Acerca de esta aplicación")
                        .font(.title2.bold())
                    
                    Text("Aquí va la descripción detallada de la app. Al scrollear, la imagen del banner se mantiene fija arriba y el contenido se desplaza normalmente como en la App Store de iOS.")
                        .foregroundColor(.secondary)
                        .lineSpacing(6)
                }
                .padding(20)
            }
        }
        .background(Color(UIColor.systemBackground))
        .transition(.asymmetric(insertion: .identity, removal: .offset(y: 1)))
    }
}

#Preview {
    AppStoreExpansionView()
}
