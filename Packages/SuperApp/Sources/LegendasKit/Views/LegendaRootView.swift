import SwiftUI
import UniformTypeIdentifiers

/// Local fixo oferecido pelo app hospedeiro (ex.: a pasta de downloads do iTorrent).
public struct LegendaLocation: Identifiable, Hashable {
    public let name: String
    public let url: URL
    public let systemImage: String
    public var id: String { url.path }

    public init(name: String, url: URL, systemImage: String = "folder") {
        self.name = name
        self.url = url
        self.systemImage = systemImage
    }
}

/// Tela inicial da aba Legenda: os locais e as pastas adicionadas.
struct LegendaRootView: View {
    let builtIn: [LegendaLocation]
    @StateObject private var settings = LegendaSettings.shared
    @State private var importing = false
    @State private var showSettings = false
    @State private var error: String?
    @State private var unlockPassword = ""
    @State private var unlocking = false

    var body: some View {
        NavigationStack {
            List {
                if !settings.hasApiKey {
                    Section {
                        SecureField(L("Senha"), text: $unlockPassword)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit(unlock)
                        Button(action: unlock) {
                            HStack { Text(L("Desbloquear chave")); if unlocking { Spacer(); ProgressView() } }
                        }
                        .disabled(unlockPassword.isEmpty || unlocking)
                    } header: {
                        Text(L("Ativar a aba Legenda"))
                    } footer: {
                        Text(L("Digite a senha uma vez para liberar a chave do OpenSubtitles que já vem criptografada no app. Ela fica guardada no Keychain."))
                    }
                    Section {
                        Label(L("Falta a chave da API do OpenSubtitles"), systemImage: "key.fill").foregroundStyle(.orange)
                        Text(L("Sem ela o app não consegue buscar legendas. A chave é gratuita: crie uma conta no OpenSubtitles.com e gere a chave em API consumers."))
                            .font(.footnote).foregroundStyle(.secondary)
                        Button(L("Configurar agora")) { showSettings = true }
                    }
                }

                Section {
                    ForEach(builtIn) { loc in
                        NavigationLink {
                            FolderView(folder: loc.url, title: loc.name, scopeRoot: nil)
                        } label: {
                            Label(loc.name, systemImage: loc.systemImage)
                        }
                    }
                    ForEach(settings.savedFolders) { f in
                        NavigationLink {
                            SavedFolderDestination(folder: f)
                        } label: {
                            Label(f.name, systemImage: "folder.badge.person.crop")
                        }
                    }
                    .onDelete { idx in idx.map { settings.savedFolders[$0] }.forEach(settings.removeFolder) }

                    Button { importing = true } label: {
                        Label(L("Adicionar pasta…"), systemImage: "plus.circle")
                    }
                } header: {
                    Text(L("Locais"))
                } footer: {
                    Text(L("Adicione pastas do app Arquivos: No meu iPhone, iCloud Drive ou um servidor de rede (SMB). Toque num vídeo para buscar a legenda; ela é salva ao lado do vídeo, com o mesmo nome."))
                }

                Section {
                    HStack {
                        Text(L("Idiomas"))
                        Spacer()
                        Text(settings.searchLanguages.map(\.name).joined(separator: " · "))
                            .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                    if let r = settings.remainingDownloads, let at = settings.remainingUpdatedAt, Date().timeIntervalSince(at) < 86_400 {
                        LabeledContent(L("Downloads restantes hoje"), value: "\(r)")
                    }
                }
            }
            .navigationTitle(L("Legenda"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(L("Ajustes"))
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource() else { error = L("O iOS não liberou o acesso a esta pasta."); return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do { try settings.addFolder(url) } catch { self.error = error.localizedDescription }
                case .failure(let e):
                    error = e.localizedDescription
                }
            }
            .sheet(isPresented: $showSettings) { LegendaSettingsView() }
            .alert(L("Erro"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L("OK"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
        .legendaToast()
    }
}

/// Abre uma pasta salva (resolve o bookmark só quando a tela aparece).
struct SavedFolderDestination: View {
    let folder: SavedFolder
    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let url {
                FolderView(folder: url, title: folder.name, scopeRoot: url)
            } else if failed {
                EmptyFolderMessage(text: L("Não foi possível abrir esta pasta. Remova e adicione de novo."))
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard url == nil else { return }
            if let u = LegendaSettings.shared.resolve(folder) { url = u } else { failed = true }
        }
    }
}

extension LegendaRootView {
    func unlock() {
        let pw = unlockPassword
        guard !pw.isEmpty, !unlocking else { return }
        unlocking = true
        Task {
            // 600 mil rodadas de PBKDF2: roda fora da tela principal.
            let key = await Task.detached(priority: .userInitiated) {
                EmbeddedKey.unlock(EmbeddedKey.openSubtitles, password: pw)
            }.value
            unlocking = false
            if let key, !key.isEmpty {
                settings.apiKey = key
                unlockPassword = ""
                LegendaToast.shared.show(L("Chave liberada. Já dá para buscar legendas."))
            } else {
                error = L("Senha incorreta.")
            }
        }
    }
}

struct EmptyFolderMessage: View {
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 44)).foregroundStyle(.secondary)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Aviso rápido

struct LegendaToastOverlay: ViewModifier {
    @ObservedObject var toast = LegendaToast.shared
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let m = toast.message {
                Text(m).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 16).padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: toast.message)
    }
}

extension View {
    func legendaToast() -> some View { modifier(LegendaToastOverlay()) }
}
