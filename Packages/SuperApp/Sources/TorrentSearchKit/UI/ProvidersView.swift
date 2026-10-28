import SwiftUI

struct ProvidersView: View {
    @EnvironmentObject var app: AppState
    @State private var filter = ""
    @State private var categoryFilter: Category = .all
    @State private var solving: ProviderBox?
    @State private var editing: TorznabConfig?
    @State private var confirmReset = false
    @State private var statusMessage: String?
    @State private var updating = false

    struct ProviderBox: Identifiable { let p: SearchProvider; var id: String { p.id } }

    var body: some View {
        let providers = app.allProviders
            .filter { categoryFilter == .all || $0.supportedCategories.contains(categoryFilter) }
            .filter { filter.trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        List {
            if updating || statusMessage != nil {
                Section {
                    HStack {
                        if updating { ProgressView() }
                        Text(updating ? L("Atualizando status de proteção…") : statusMessage ?? "").font(.subheadline)
                    }
                }
            }
            Section {
                CategoryChips(selection: $categoryFilter, categories: app.visibleCategories)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            } footer: {
                Text(L("Buscadores com 🔒 usam proteção do Cloudflare: toque em “Desbloquear” e passe pela verificação uma vez."))
            }
            Section(L("%ld de %ld ativos", app.enabledProviders().count, app.allProviders.count)) {
                ForEach(providers, id: \.id) { p in row(p) }
            }
            Section {
                Button { editing = TorznabConfig(id: UUID().uuidString, searchProviderName: "", url: "", apiKey: "", supportedCategories: []) } label: {
                    Label(L("Adicionar buscador Torznab (Jackett/Prowlarr)"), systemImage: "plus.circle")
                }
            } footer: {
                Text(L("Torznab permite usar seu próprio servidor Jackett ou Prowlarr. A chave de API fica guardada no Keychain do iPhone."))
            }
        }
        .searchable(text: $filter, prompt: L("Buscar buscadores"))
        .navigationTitle(L("Buscadores"))
        .toolbar {
            Menu {
                Button { app.enableAll(providers.map(\.id)) } label: { Label(L("Ativar todos"), systemImage: "checkmark.circle") }
                Button { app.disableAll(providers.map(\.id)) } label: { Label(L("Desativar todos"), systemImage: "xmark.circle") }
                Button { Task { await updateStatus() } } label: { Label(L("Atualizar status de proteção"), systemImage: "shield") }
                Button(role: .destructive) { confirmReset = true } label: { Label(L("Restaurar padrão"), systemImage: "arrow.counterclockwise") }
            } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(L("Opções")) }
        }
        .sheet(item: $solving) { box in
            CloudflareSolverView(provider: box.p) { ok in
                if ok { app.unlockProvider(box.p.id); app.setEnabled(box.p.id, true); Toast.shared.show(L("%@ desbloqueado", box.p.name)) }
                else { Toast.shared.show(L("Não foi possível desbloquear")) }
            }
        }
        .sheet(item: $editing) { TorznabEditView(config: $0).environmentObject(app) }
        .confirmationDialog(L("Restaurar padrão?"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("Restaurar"), role: .destructive) { app.resetProvidersToDefault() }
        } message: {
            Text(L("Os buscadores ativos voltam ao conjunto recomendado e os cookies dos buscadores desbloqueados são apagados."))
        }
    }

    @ViewBuilder private func row(_ p: SearchProvider) -> some View {
        let status = app.protection(p)
        let isTorznab = p is TorznabSearchProvider
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.name).font(.body.weight(.medium))
                        if status == .locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.orange) }
                        if status == .unlocked { Image(systemName: "lock.open.fill").font(.caption).foregroundStyle(.green) }
                        if isTorznab { Text("Torznab").font(.caption2).padding(.horizontal, 5).background(Color.purple.opacity(0.2), in: Capsule()) }
                    }
                    Text(URL(string: p.url)?.host ?? p.url).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if status == .locked {
                    Button(L("Desbloquear")) { solving = ProviderBox(p: p) }.buttonStyle(.bordered).controlSize(.small)
                } else {
                    Toggle(p.name, isOn: Binding(get: { app.isEnabled(p.id) }, set: { app.setEnabled(p.id, $0) })).labelsHidden()
                }
            }
            Text(p.supportedCategories.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary)
            if case .unsafe(let reason) = p.safety {
                Label(reason, systemImage: "exclamationmark.shield").font(.caption2).foregroundStyle(.red)
            }
        }
        .swipeActions {
            if isTorznab {
                Button(role: .destructive) { app.deleteTorznab(p.id) } label: { Label(L("Apagar"), systemImage: "trash") }
                Button { editing = (p as? TorznabSearchProvider)?.config } label: { Label(L("Editar"), systemImage: "pencil") }
            }
        }
    }

    private func updateStatus() async {
        updating = true; statusMessage = nil
        if let r = await app.updateProtectionStatus() {
            statusMessage = L("%ld liberados, %ld precisam de desbloqueio", r.unlocked, r.locked)
        } else { statusMessage = L("Algo deu errado. Verifique a conexão.") }
        updating = false
    }
}

struct TorznabEditView: View {
    @State var config: TorznabConfig
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false
    @State private var checkResult: TorznabConnectionResult?
    @State private var detecting = false

    private var urlValid: Bool {
        guard let u = URL(string: config.url), let s = u.scheme, ["http", "https"].contains(s), u.host != nil else { return false }
        return true
    }
    private var canSave: Bool { !config.searchProviderName.trimmed.isEmpty && urlValid && !config.apiKey.isEmpty && !config.supportedCategories.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Nome"), text: $config.searchProviderName)
                    TextField("URL", text: $config.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !config.url.isEmpty && !urlValid { Text(L("URL inválida")).font(.caption).foregroundStyle(.red) }
                    SecureField(L("Chave de API"), text: $config.apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text(L("Ex.: http://192.168.0.10:9117/api/v2.0/indexers/all/results/torznab"))
                }
                Section {
                    Button {
                        Task { checking = true; checkResult = await TorznabUtils.checkConnection(apiUrl: config.url, apiKey: config.apiKey); checking = false }
                    } label: { HStack { Text(checking ? L("Verificando conexão…") : L("Verificar conexão")); if checking { Spacer(); ProgressView() } } }
                    .disabled(!urlValid || config.apiKey.isEmpty || checking)
                    if let r = checkResult {
                        Label(r.message, systemImage: r == .established ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(r == .established ? .green : .red)
                    }
                }
                Section {
                    ForEach(Category.allCases.filter { $0 != .all && (app.nsfwMode || !$0.isNSFW) }) { c in
                        Toggle(c.title, isOn: Binding(
                            get: { config.supportedCategories.contains(c) },
                            set: { if $0 { config.supportedCategories.insert(c) } else { config.supportedCategories.remove(c) } }))
                    }
                    Button {
                        Task {
                            detecting = true
                            if let cats = try? await TorznabUtils.supportedCategories(apiUrl: config.url, apiKey: config.apiKey) {
                                config.supportedCategories = cats
                            } else { Toast.shared.show(L("Não foi possível detectar as categorias")) }
                            detecting = false
                        }
                    } label: { Text(detecting ? L("Detectando categorias…") : L("Detectar categorias automaticamente")) }
                    .disabled(!urlValid || config.apiKey.isEmpty || detecting)
                } header: { Text(L("Categorias suportadas")) } footer: { Text(L("Selecione uma ou mais categorias")) }
            }
            .navigationTitle(app.torznabConfigs.contains { $0.id == config.id } ? L("Editar buscador") : L("Adicionar buscador"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancelar")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Salvar")) {
                        let isNew = !app.torznabConfigs.contains { $0.id == config.id }
                        app.saveTorznab(config)
                        if isNew { app.setEnabled(config.id, true) }
                        dismiss()
                    }.disabled(!canSave)
                }
            }
        }
    }
}
