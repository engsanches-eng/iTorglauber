import SwiftUI

struct SettingsView: View {
    var showsClose = false
    @EnvironmentObject var app: AppState
    @State private var confirmClearViewed = false
    @State private var confirmErase = false
    @State private var maxResultsText = ""
    @State private var safari: IdentifiableURL?

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Idioma")) {
                    Button(L("Idioma do app")) {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                }

                Section {
                    NavigationLink {
                        ProvidersView()
                    } label: {
                        LabeledContent(L("Buscadores"), value: L("%ld de %ld ativos", app.enabledProviders().count, app.allProviders.count))
                    }
                    Picker(L("Ordenar resultados por"), selection: $app.defaultSort.criteria) {
                        ForEach(SortCriteria.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(L("Ordem padrão"), selection: $app.defaultSort.order) {
                        ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(L("Número máximo de resultados"), selection: Binding(get: { app.maxNumResults ?? -1 }, set: { app.maxNumResults = $0 < 0 ? nil : $0 })) {
                        Text(L("Ilimitado")).tag(-1)
                        ForEach([50, 100, 200, 500, 1000], id: \.self) { Text("\($0)").tag($0) }
                    }
                } header: { Text(L("Busca")) }

                Section {
                    Toggle(L("Salvar histórico de buscas"), isOn: $app.saveSearchHistory)
                    Toggle(L("Sugerir buscas anteriores"), isOn: $app.showSearchHistory)
                    Toggle(L("Mostrar buscas recentes no início"), isOn: $app.showRecentSearches)
                    NavigationLink(L("Histórico de buscas")) { HistoryView() }
                } header: { Text(L("Histórico")) } footer: { Text(L("O histórico fica salvo só neste iPhone.")) }

                Section {
                    Toggle(L("Modo NSFW (conteúdo adulto)"), isOn: $app.nsfwMode)
                    Button(L("Limpar torrents vistos")) { confirmClearViewed = true }.disabled(app.viewedIds.isEmpty)
                } header: { Text(L("Conteúdo e privacidade")) } footer: {
                    Text(L("Com o modo NSFW desligado, a categoria Adulto, os resultados adultos e os buscadores marcados como inseguros ficam ocultos."))
                }

                Section {
                    Toggle(L("Verificar buscadores ao abrir"), isOn: $app.checkProvidersOnStartup)
                } header: { Text(L("Rede")) } footer: {
                    Text(L("Verifica quais buscadores protegidos pelo Cloudflare ainda estão liberados. Para DNS criptografado (DoH), use um perfil de DNS ou VPN no iOS."))
                }

                Section(L("Privacidade")) {
                    Label(L("Sem anúncios, analytics ou rastreamento"), systemImage: "hand.raised.fill")
                    Label(L("O app só se conecta aos sites dos buscadores que você ativar"), systemImage: "network")
                    Label(L("Favoritos, histórico e ajustes ficam só neste iPhone, criptografados pelo iOS"), systemImage: "lock.iphone")
                    Button(role: .destructive) { confirmErase = true } label: { Label(L("Apagar todos os dados do app"), systemImage: "trash") }
                }

                Section(L("Sobre")) {
                    LabeledContent(L("Versão"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    Button(L("Código-fonte do app original (Android)")) {
                        safari = IdentifiableURL(url: URL(string: "https://github.com/prajwalch/TorrentSearch")!)
                    }
                    Text(L("Versão para iPhone baseada no TorrentSearch de Prajwal Chapagain (licença MIT)."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Ajustes"))
            .closeButton(showsClose)
            .sheet(item: $safari) { SafariView(url: $0.url).ignoresSafeArea() }
            .confirmationDialog(L("Limpar todos os torrents vistos?"), isPresented: $confirmClearViewed, titleVisibility: .visible) {
                Button(L("Limpar"), role: .destructive) { app.viewedIds = [] }
            }
            .confirmationDialog(L("Apagar todos os dados?"), isPresented: $confirmErase, titleVisibility: .visible) {
                Button(L("Apagar tudo"), role: .destructive) { app.eraseAllData() }
            } message: {
                Text(L("Favoritos, histórico, configurações Torznab, cookies e cache serão apagados."))
            }
        }
    }
}
