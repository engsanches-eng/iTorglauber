import SwiftUI
import SafariServices

/// Ajustes da aba Legenda: idioma primário e secundário (como no Windows), comportamento e conta.
struct LegendaSettingsView: View {
    @ObservedObject private var settings = LegendaSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var picking: Slot?
    @State private var password = LegendaSettings.shared.password
    @State private var loggingIn = false
    @State private var message: String?
    @State private var showConsumers = false

    enum Slot: String, Identifiable { case primary, secondary; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { picking = .primary } label: {
                        LabeledContent(L("Idioma primário"), value: settings.primary.name).foregroundStyle(.primary)
                    }
                    Button { picking = .secondary } label: {
                        LabeledContent(L("Idioma secundário"), value: settings.secondary?.name ?? L("Nenhum")).foregroundStyle(.primary)
                    }
                } header: {
                    Text(L("Idiomas"))
                } footer: {
                    Text(L("A busca usa os dois idiomas. \"Melhor legenda\" tenta o primário e, se não houver, o secundário."))
                }

                Section(L("Comportamento")) {
                    Picker(L("Ao tocar no vídeo"), selection: $settings.tapAction) {
                        ForEach(LegendaSettings.TapAction.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(L("Nome do arquivo"), selection: $settings.naming) {
                        ForEach(LegendaSettings.Naming.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(L("Se a legenda já existir"), selection: $settings.conflict) {
                        ForEach(LegendaSettings.Conflict.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle(L("Incluir legendas para surdos"), isOn: $settings.includeHearingImpaired)
                    Toggle(L("Incluir traduções automáticas"), isOn: $settings.includeMachineTranslated)
                }

                Section {
                    SecureField(L("Chave da API"), text: $settings.apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(L("Criar uma chave grátis no OpenSubtitles")) { showConsumers = true }
                } header: {
                    Text(L("OpenSubtitles"))
                } footer: {
                    Text(L("Crie uma conta grátis em opensubtitles.com, abra API consumers e gere uma chave. Ela fica guardada no Keychain do iPhone."))
                }

                Section {
                    if let user = settings.loggedInUser {
                        LabeledContent(L("Conectado como"), value: user)
                        if let r = settings.remainingDownloads {
                            LabeledContent(L("Downloads restantes hoje"), value: "\(r)")
                        }
                        Button(L("Sair"), role: .destructive) {
                            settings.logout()
                            password = ""
                            message = nil
                        }
                    } else {
                        TextField(L("Usuário"), text: $settings.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                        SecureField(L("Senha"), text: $password).textContentType(.password)
                        Button {
                            Task { await login() }
                        } label: {
                            HStack { Text(L("Entrar")); if loggingIn { Spacer(); ProgressView() } }
                        }
                        .disabled(loggingIn || settings.username.trimmed.isEmpty || password.isEmpty || !settings.hasApiKey)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text(L("Conta (opcional)"))
                } footer: {
                    Text(L("Sem conta, o OpenSubtitles libera poucos downloads por dia. Com a conta grátis o limite aumenta. Buscar não gasta o limite; só baixar."))
                }

                Section(L("Privacidade")) {
                    Label(L("O app só conversa com api.opensubtitles.com, por HTTPS"), systemImage: "lock.shield")
                    Label(L("Enviados: o hash do vídeo, o nome do arquivo e os idiomas"), systemImage: "doc.text.magnifyingglass")
                    Label(L("Sem anúncios, analytics ou rastreamento"), systemImage: "hand.raised.fill")
                }
            }
            .navigationTitle(L("Ajustes de legenda"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Concluído")) { dismiss() } } }
            .sheet(item: $picking) { slot in
                switch slot {
                case .primary:
                    LanguagePickerView(title: L("Idioma primário"), selected: settings.primary) { settings.primary = $0 }
                case .secondary:
                    LanguagePickerView(title: L("Idioma secundário"), selected: settings.secondary, allowNone: true,
                                       onPick: { settings.secondary = $0 }, onNone: { settings.secondary = nil })
                }
            }
            .sheet(isPresented: $showConsumers) {
                LegendaSafari(url: URL(string: "https://www.opensubtitles.com/consumers")!).ignoresSafeArea()
            }
        }
    }

    private func login() async {
        loggingIn = true
        message = nil
        settings.password = password
        do {
            try await LegendaEngine.shared.login()
            message = L("Conectado.")
        } catch {
            settings.password = ""
            message = error.localizedDescription
        }
        loggingIn = false
    }
}

struct LegendaSafari: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
