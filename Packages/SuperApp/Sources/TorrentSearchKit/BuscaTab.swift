import SwiftUI
import UIKit

/// Ponto de entrada da aba "Buscar" no superapp.
public enum BuscaTab {
    /// O app hospedeiro (iTorrent) recebe aqui os links magnet e adiciona o download.
    /// Retorna true se o link foi aceito.
    @MainActor public static var openMagnet: (@MainActor (URL) -> Bool)?

    public static var title: String { L("Buscar") }

    /// Tela raiz da aba, pronta para pôr numa UITabBarController.
    @MainActor public static func makeViewController() -> UIViewController {
        let vc = UIHostingController(rootView: BuscaRootView())
        vc.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: "magnifyingglass"), tag: 0)
        return vc
    }
}

/// Raiz da aba Buscar: a tela inicial de busca, com Explorar, Favoritos e Ajustes no topo.
struct BuscaRootView: View {
    @StateObject private var app = AppState.shared
    @State private var checkedProviders = false

    var body: some View {
        HomeView()
            .environmentObject(app)
            .toastOverlay()
            // Primeira execução: pergunta se quer ativar os buscadores recomendados (como no original).
            .alert(L("Ativar buscadores"), isPresented: Binding(get: { app.enabledProviderIds == nil }, set: { _ in })) {
                Button(L("Ativar recomendados")) { app.enableDefaultProviders() }
                Button(L("Vou escolher"), role: .cancel) { app.skipDefaultProviders() }
            } message: {
                Text(L("Nenhum buscador está ativo ainda. Quer ativar os recomendados?"))
            }
            .task {
                guard !checkedProviders, app.checkProvidersOnStartup, app.enabledProviderIds != nil else { return }
                checkedProviders = true
                if let r = await app.updateProtectionStatus(), r.locked > 0 {
                    Toast.shared.show(L("%ld buscadores precisam de desbloqueio", r.locked))
                }
            }
    }
}
