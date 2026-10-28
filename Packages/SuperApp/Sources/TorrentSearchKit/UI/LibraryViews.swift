import SwiftUI
import UniformTypeIdentifiers

// MARK: - Explorar (mais recentes / em alta)

struct BrowseView: View {
    var showsClose = false
    @EnvironmentObject var app: AppState
    enum Mode: String, CaseIterable, Identifiable { case latest, top; var id: String { rawValue } }
    @State private var mode: Mode = .latest
    @State private var category: Category = .all
    @State private var results = SearchResults()
    @State private var loading = false
    @State private var filter = ""
    @State private var selected: Torrent?
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            let list = results.torrents
                .filter { app.nsfwMode || !$0.isNSFW }
                .filter { filter.trimmed.isEmpty || SearchService.matches($0, query: filter) }
            List {
                Section {
                    Picker(L("Modo"), selection: $mode) {
                        Text(L("Mais recentes")).tag(Mode.latest)
                        Text(L("Em alta")).tag(Mode.top)
                    }
                    .pickerStyle(.segmented)
                    CategoryChips(selection: $category, categories: app.visibleCategories)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if !list.isEmpty {
                    Section(L("%ld torrents", list.count)) {
                        ForEach(list) { t in
                            Button { selected = t } label: { TorrentRow(torrent: t, viewed: app.viewedIds.contains(t.id), bookmarked: app.isBookmarked(t)) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .overlay {
                if !loading && list.isEmpty {
                    EmptyStateView(systemImage: "sparkles", title: L("Nada para mostrar"),
                                   message: L("Os buscadores necessários podem estar desativados ou fora do ar."),
                                   actionTitle: L("Tentar de novo")) { load() }
                }
            }
            .searchable(text: $filter, prompt: L("Filtrar"))
            .navigationTitle(L("Explorar"))
            .closeButton(showsClose)
            .refreshable { load() }
            .sheet(item: $selected) { TorrentActionsSheet(torrent: $0).environmentObject(app) }
            .onChange(of: mode) { _ in load() }
            .onChange(of: category) { _ in load() }
            .task { if results.totalProviders == 0 { load() } }
        }
    }

    private func load() {
        task?.cancel()
        loading = true
        results = SearchResults()
        let providers = app.enabledProviders()
        let stream = mode == .latest ? SearchService.latest(category: category, providers: providers)
                                     : SearchService.top(category: category, providers: providers)
        task = Task { @MainActor in
            for await r in stream { results = r }
            loading = false
        }
    }
}

// MARK: - Favoritos

struct BookmarksView: View {
    var showsClose = false
    @EnvironmentObject var app: AppState
    @State private var filter = ""
    @State private var selected: Torrent?
    @State private var confirmDelete = false
    @State private var exporting = false
    @State private var importing = false

    var body: some View {
        NavigationStack {
            let items = SearchService.sort(app.bookmarks.map(\.torrent), by: app.bookmarksSort)
                .filter { filter.trimmed.isEmpty || SearchService.matches($0, query: filter) }
            List {
                ForEach(items) { t in
                    Button { selected = t } label: { TorrentRow(torrent: t) }.buttonStyle(.plain)
                        .swipeActions { Button(role: .destructive) { app.toggleBookmark(t) } label: { Label(L("Apagar"), systemImage: "trash") } }
                }
            }
            .overlay {
                if items.isEmpty {
                    EmptyStateView(systemImage: "bookmark", title: app.bookmarks.isEmpty ? L("Nenhum favorito") : L("Nenhum favorito encontrado"),
                                   message: app.bookmarks.isEmpty ? L("Deslize um resultado para a esquerda ou use o menu do torrent para favoritar.") : nil)
                }
            }
            .searchable(text: $filter, prompt: L("Buscar nos favoritos"))
            .navigationTitle(L("Favoritos"))
            .closeButton(showsClose)
            .toolbar {
                Menu {
                    Picker(L("Ordenar por"), selection: $app.bookmarksSort.criteria) {
                        ForEach(SortCriteria.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(L("Ordem"), selection: $app.bookmarksSort.order) {
                        ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Button { importing = true } label: { Label(L("Importar de arquivo"), systemImage: "square.and.arrow.down") }
                    Button { exporting = true } label: { Label(L("Exportar para arquivo"), systemImage: "square.and.arrow.up") }
                        .disabled(app.bookmarks.isEmpty)
                    Button(role: .destructive) { confirmDelete = true } label: { Label(L("Apagar todos"), systemImage: "trash") }
                        .disabled(app.bookmarks.isEmpty)
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(L("Opções")) }
            }
            .sheet(item: $selected) { TorrentActionsSheet(torrent: $0).environmentObject(app) }
            .confirmationDialog(L("Apagar todos os favoritos?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("Apagar"), role: .destructive) { app.bookmarks = [] }
            } message: { Text(L("Os favoritos serão removidos permanentemente.")) }
            .fileExporter(isPresented: $exporting, document: JSONFile(data: (try? JSONEncoder().encode(app.bookmarks)) ?? Data()),
                          contentType: .json, defaultFilename: "torrentsearch_favoritos") { _ in }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Bookmark].self, from: data) else {
                    Toast.shared.show(L("Arquivo inválido")); return
                }
                let existing = Set(app.bookmarks.map(\.id))
                app.bookmarks.append(contentsOf: list.filter { !existing.contains($0.id) })
                Toast.shared.show(L("%ld favoritos importados", list.count))
            }
        }
    }
}

struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

// MARK: - Histórico de buscas

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @State private var confirmClear = false

    var body: some View {
        let cal = Calendar.current
        let groups = Dictionary(grouping: app.history) { cal.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }
        List {
            ForEach(groups, id: \.key) { day, items in
                Section(cal.isDateInToday(day) ? L("Hoje") : cal.isDateInYesterday(day) ? L("Ontem") : Fmt.date.string(from: day)) {
                    ForEach(items) { h in
                        NavigationLink(value: SearchRoute(query: h.query, category: .all)) { Text(h.query) }
                            .swipeActions { Button(role: .destructive) { app.history.removeAll { $0.id == h.id } } label: { Label(L("Apagar"), systemImage: "trash") } }
                            .contextMenu {
                                Button { MagnetOpener.copy(h.query); Toast.shared.show(L("Busca copiada!")) } label: { Label(L("Copiar"), systemImage: "doc.on.doc") }
                            }
                    }
                }
            }
        }
        .overlay { if app.history.isEmpty { EmptyStateView(systemImage: "clock", title: L("Nenhuma busca no histórico")) } }
        .navigationTitle(L("Histórico de buscas"))
        .navigationDestination(for: SearchRoute.self) { SearchView(query: $0.query, category: $0.category) }
        .toolbar {
            Button(L("Limpar"), role: .destructive) { confirmClear = true }.disabled(app.history.isEmpty)
        }
        .confirmationDialog(L("Limpar o histórico de buscas?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L("Limpar"), role: .destructive) { app.history = [] }
        }
    }
}
