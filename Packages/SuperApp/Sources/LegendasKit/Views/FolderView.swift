import SwiftUI

/// Mantém o acesso a uma pasta escolhida no app Arquivos enquanto a tela está aberta.
final class ScopedAccess: ObservableObject {
    private var url: URL?
    private var started = false

    func begin(_ url: URL?) {
        guard !started, let url else { return }
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }

    deinit { if started { url?.stopAccessingSecurityScopedResource() } }
}

/// Pedido de busca em andamento (abre a lista de legendas).
struct SearchRequest: Identifiable {
    let id = UUID()
    let video: FolderItem
    let languages: [SubtitleLanguage]
}

/// Legenda escolhida esperando decisão porque já existe uma com o mesmo nome.
struct PendingSave: Identifiable {
    let id = UUID()
    let result: SubtitleResult
    let video: FolderItem
    let target: URL
}

/// Navegador de pastas. Tocar num vídeo faz o papel do "botão direito" do Windows.
struct FolderView: View {
    let folder: URL
    let title: String
    /// Pasta escolhida no Arquivos que dá o acesso (nil para pastas do próprio app).
    let scopeRoot: URL?

    @StateObject private var access = ScopedAccess()
    @ObservedObject private var settings = LegendaSettings.shared
    @State private var items: [FolderItem] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var filter = ""
    @State private var menuFor: FolderItem?
    @State private var searchRequest: SearchRequest?
    @State private var languagePickerFor: FolderItem?
    @State private var pending: PendingSave?
    @State private var busy: String?
    @State private var alert: AlertInfo?
    @State private var showSettings = false
    @State private var confirmDelete: FolderItem?

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var offerSettings = false
        var offerManualSearch: FolderItem?
    }

    private var visible: [FolderItem] {
        items.filter { item in
            (!settings.onlyVideos || item.kind == .folder || item.kind == .video)
                && (filter.trimmed.isEmpty || item.name.localizedCaseInsensitiveContains(filter.trimmed))
        }
    }

    var body: some View {
        List {
            if let loadError {
                EmptyFolderMessage(text: loadError).listRowBackground(Color.clear)
            } else if loaded && visible.isEmpty {
                EmptyFolderMessage(text: settings.onlyVideos ? L("Nenhum vídeo nesta pasta.") : L("Pasta vazia."))
                    .listRowBackground(Color.clear)
            }
            ForEach(visible) { item in row(item) }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .searchable(text: $filter, prompt: L("Filtrar por nome"))
        .refreshable { reload() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Toggle(isOn: $settings.onlyVideos) { Label(L("Mostrar só vídeos"), systemImage: "film") }
                    Button { reload() } label: { Label(L("Atualizar"), systemImage: "arrow.clockwise") }
                    Button { showSettings = true } label: { Label(L("Ajustes de legenda"), systemImage: "gearshape") }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel(L("Opções"))
            }
        }
        .onAppear {
            access.begin(scopeRoot)
            if !loaded { reload() }
        }
        .overlay { if let busy { BusyOverlay(text: busy) } }
        .confirmationDialog(menuFor?.name ?? "", isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }), titleVisibility: .visible, presenting: menuFor) { item in
            actionButtons(for: item)
        }
        .sheet(item: $searchRequest) { req in
            SubtitleResultsView(video: req.video, languages: req.languages) { picked in
                searchRequest = nil
                startSave(picked, video: req.video)
            }
        }
        .sheet(item: $languagePickerFor) { item in
            LanguagePickerView(title: L("Buscar em outro idioma"), selected: nil) { lang in
                languagePickerFor = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    searchRequest = SearchRequest(video: item, languages: [lang])
                }
            }
        }
        .sheet(isPresented: $showSettings) { LegendaSettingsView() }
        .confirmationDialog(L("Já existe uma legenda com este nome"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { p in
            Button(L("Substituir"), role: .destructive) { perform(p.result, video: p.video, target: p.target) }
            Button(L("Manter as duas")) {
                perform(p.result, video: p.video, target: SubtitleWriter.alternativeURL(for: p.target, language: p.result.language))
            }
            Button(L("Cancelar"), role: .cancel) {}
        } message: { p in
            Text(p.target.lastPathComponent)
        }
        .confirmationDialog(L("Apagar a legenda deste vídeo?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible, presenting: confirmDelete) { item in
            Button(L("Apagar"), role: .destructive) { deleteSubtitles(of: item) }
        } message: { item in
            Text(FileBrowser.subtitles(for: item.url).map(\.lastPathComponent).joined(separator: "\n"))
        }
        .alert(item: $alert) { a in
            if a.offerSettings {
                return Alert(title: Text(a.title), message: Text(a.message),
                             primaryButton: .default(Text(L("Abrir ajustes"))) { showSettings = true },
                             secondaryButton: .cancel(Text(L("OK"))))
            }
            if let v = a.offerManualSearch {
                return Alert(title: Text(a.title), message: Text(a.message),
                             primaryButton: .default(Text(L("Buscar em outro idioma"))) { languagePickerFor = v },
                             secondaryButton: .cancel(Text(L("OK"))))
            }
            return Alert(title: Text(a.title), message: Text(a.message), dismissButton: .cancel(Text(L("OK"))))
        }
    }

    // MARK: Linhas

    @ViewBuilder private func row(_ item: FolderItem) -> some View {
        switch item.kind {
        case .folder:
            NavigationLink {
                FolderView(folder: item.url, title: item.name, scopeRoot: scopeRoot)
            } label: {
                ItemRow(item: item)
            }
        case .video:
            Button { tapped(item) } label: { ItemRow(item: item) }
                .buttonStyle(.plain)
                .contextMenu { actionButtons(for: item) }
        default:
            ItemRow(item: item).foregroundStyle(.secondary)
        }
    }

    /// As mesmas opções do menu do Windows, com os idiomas dos ajustes.
    @ViewBuilder private func actionButtons(for item: FolderItem) -> some View {
        Button { runBest(item) } label: {
            Label(L("Melhor legenda (%@)", settings.primary.name), systemImage: "star")
        }
        Button { search(item, [settings.primary]) } label: {
            Label(L("Buscar em %@", settings.primary.name), systemImage: "magnifyingglass")
        }
        if let s = settings.secondary, s != settings.primary {
            Button { search(item, [s]) } label: {
                Label(L("Buscar em %@", s.name), systemImage: "magnifyingglass")
            }
        }
        Button { languagePickerFor = item } label: {
            Label(L("Buscar em outro idioma…"), systemImage: "globe")
        }
        if item.hasSubtitle {
            Button(role: .destructive) { confirmDelete = item } label: {
                Label(L("Apagar legenda"), systemImage: "trash")
            }
        }
    }

    // MARK: Ações

    private func tapped(_ item: FolderItem) {
        if item.isCloudPlaceholder {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: item.url)
                LegendaToast.shared.show(L("Baixando o vídeo do iCloud… Tente de novo em instantes."))
            } catch {
                alert = AlertInfo(title: L("iCloud"), message: error.localizedDescription)
            }
            return
        }
        guard settings.hasApiKey else { missingKey(); return }
        switch settings.tapAction {
        case .menu: menuFor = item
        case .best: runBest(item)
        }
    }

    private func search(_ item: FolderItem, _ langs: [SubtitleLanguage]) {
        guard settings.hasApiKey else { missingKey(); return }
        searchRequest = SearchRequest(video: item, languages: langs)
    }

    private func missingKey() {
        alert = AlertInfo(title: L("Falta a chave da API do OpenSubtitles"),
                          message: L("Configure a chave da API do OpenSubtitles em Ajustes."), offerSettings: true)
    }

    private func runBest(_ item: FolderItem) {
        guard settings.hasApiKey else { missingKey(); return }
        busy = L("Buscando legendas…")
        Task {
            do {
                let results = try await LegendaEngine.shared.search(video: item.url, languages: settings.searchLanguages)
                busy = nil
                if let best = LegendaEngine.shared.best(from: results) {
                    startSave(best, video: item)
                } else {
                    alert = AlertInfo(title: L("Nenhuma legenda encontrada"),
                                      message: L("Nenhuma legenda compatível foi encontrada para este arquivo."),
                                      offerManualSearch: item)
                }
            } catch {
                busy = nil
                show(error)
            }
        }
    }

    private func startSave(_ result: SubtitleResult, video: FolderItem) {
        var target = SubtitleWriter.targetURL(video: video.url, language: result.language, naming: settings.naming)
        if FileManager.default.fileExists(atPath: target.path) {
            switch settings.conflict {
            case .ask:
                // Espera a folha de resultados fechar antes de mostrar a pergunta.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    pending = PendingSave(result: result, video: video, target: target)
                }
                return
            case .replace: break
            case .keepBoth: target = SubtitleWriter.alternativeURL(for: target, language: result.language)
            }
        }
        perform(result, video: video, target: target)
    }

    private func perform(_ result: SubtitleResult, video: FolderItem, target: URL) {
        busy = L("Baixando legenda…")
        Task {
            do {
                let saved = try await LegendaEngine.shared.downloadAndSave(result, to: target)
                busy = nil
                var msg = L("Legenda salva: %@", saved.lastPathComponent)
                if let r = settings.remainingDownloads { msg += " · " + L("%ld downloads restantes hoje", r) }
                LegendaToast.shared.show(msg, seconds: 3.5)
                reload()
            } catch {
                busy = nil
                show(error)
            }
        }
    }

    private func deleteSubtitles(of item: FolderItem) {
        do {
            for u in FileBrowser.subtitles(for: item.url) { try SubtitleWriter.delete(u) }
            LegendaToast.shared.show(L("Legenda apagada"))
        } catch {
            alert = AlertInfo(title: L("Erro"), message: error.localizedDescription)
        }
        reload()
    }

    private func show(_ error: Error) {
        let isKey: Bool
        switch error {
        case OpenSubtitlesError.missingApiKey, OpenSubtitlesError.invalidApiKey: isKey = true
        default: isKey = false
        }
        alert = AlertInfo(title: L("Erro"), message: error.localizedDescription, offerSettings: isKey)
    }

    private func reload() {
        do {
            items = try FileBrowser.list(folder)
            loadError = nil
        } catch {
            items = []
            loadError = L("Não foi possível abrir esta pasta: %@", error.localizedDescription)
        }
        loaded = true
    }
}

// MARK: - Componentes

struct ItemRow: View {
    let item: FolderItem

    private var icon: String {
        switch item.kind {
        case .folder: return "folder.fill"
        case .video: return item.isCloudPlaceholder ? "icloud.and.arrow.down" : "film"
        case .subtitle: return "captions.bubble"
        case .other: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(item.kind == .folder ? Color.accentColor : item.kind == .video ? Color.primary : Color.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body).lineLimit(3)
                HStack(spacing: 8) {
                    if let s = item.size, item.kind != .folder {
                        Text(ByteCountFormatter.string(fromByteCount: s, countStyle: .file))
                    }
                    if let m = item.modified {
                        Text(m, style: .date)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if item.hasSubtitle {
                Text("CC")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.green)
                    .accessibilityLabel(L("Já tem legenda"))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct BusyOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(text).font(.subheadline.weight(.medium))
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
