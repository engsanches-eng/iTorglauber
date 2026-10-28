import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var results = SearchResults()
    @Published var isSearching = false
    @Published var sort: SortOptions
    @Published var filterText = ""
    @Published var showDead = true
    @Published var hideViewed = false
    @Published var excludedProviders: Set<String> = []
    @Published var categoryFilter: Category

    let query: String
    let category: Category
    private var task: Task<Void, Never>?
    private let app = AppState.shared

    init(query: String, category: Category) {
        self.query = query
        self.category = category
        self.categoryFilter = category
        self.sort = AppState.shared.defaultSort
    }

    func start() {
        stop()
        isSearching = true
        results = SearchResults()
        let providers = app.enabledProviders(category: category)
        let stream = SearchService.search(query: query, category: category, providers: providers, limit: app.maxNumResults) { id in
            Task { @MainActor in AppState.shared.lockProvider(id) }
        }
        task = Task {
            for await r in stream { self.results = r }
            self.isSearching = false
        }
    }

    func stop() { task?.cancel(); task = nil; isSearching = false }

    /// Lista exibida: filtros (NSFW, mortos, vistos, buscador, texto, categoria) + ordenação.
    var visible: [Torrent] {
        var list = results.torrents
        if !app.nsfwMode { list = list.filter { !$0.isNSFW } }
        if !showDead { list = list.filter { !$0.isDead } }
        if hideViewed { list = list.filter { !app.viewedIds.contains($0.id) } }
        if !excludedProviders.isEmpty { list = list.filter { !excludedProviders.contains($0.providerName) } }
        if categoryFilter != .all && categoryFilter != category { list = list.filter { $0.category == categoryFilter } }
        if !filterText.trimmed.isEmpty { list = list.filter { SearchService.matches($0, query: filterText) } }
        return SearchService.sort(list, by: sort)
    }

    var providerNames: [String] { Array(Set(results.torrents.map(\.providerName))).sorted() }
}

struct SearchView: View {
    @StateObject private var vm: SearchViewModel
    @EnvironmentObject var app: AppState
    @State private var selected: Torrent?
    @State private var showErrors = false
    @State private var showProviderFilter = false

    init(query: String, category: Category) {
        _vm = StateObject(wrappedValue: SearchViewModel(query: query, category: category))
    }

    var body: some View {
        let list = vm.visible
        List {
            Section {
                filtersBar
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if vm.isSearching {
                HStack(spacing: 10) {
                    ProgressView(value: Double(vm.results.finishedProviders), total: Double(max(vm.results.totalProviders, 1)))
                    Text("\(vm.results.finishedProviders)/\(vm.results.totalProviders)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            if !list.isEmpty {
                Section {
                    ForEach(list) { t in
                        Button { selected = t } label: {
                            TorrentRow(torrent: t, viewed: app.viewedIds.contains(t.id), bookmarked: app.isBookmarked(t))
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button { app.toggleBookmark(t) } label: {
                                Label(app.isBookmarked(t) ? L("Remover") : L("Favoritar"), systemImage: app.isBookmarked(t) ? "bookmark.slash" : "bookmark")
                            }.tint(.accentColor)
                        }
                        .contextMenu { contextMenu(t) }
                    }
                } header: {
                    Text(L("%ld resultados para “%@”", list.count, vm.query))
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if !vm.isSearching && list.isEmpty {
                if app.enabledProviders(category: vm.category).isEmpty {
                    EmptyStateView(systemImage: "magnifyingglass", title: L("Nenhum buscador ativo"),
                                   message: L("Ative buscadores na aba Ajustes → Buscadores."))
                } else {
                    EmptyStateView(systemImage: "tray", title: L("Nenhum resultado"),
                                   message: L("Nenhum torrent encontrado para “%@”. Tente outro termo ou ative mais buscadores.", vm.query))
                }
            }
        }
        .navigationTitle(vm.query)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $vm.filterText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L("Filtrar resultados"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !vm.results.errors.isEmpty {
                    Button { showErrors = true } label: {
                        Label(L("Ver erros"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
                sortMenu
                if vm.isSearching {
                    Button { vm.stop() } label: { Label(L("Parar busca"), systemImage: "stop.circle") }
                } else {
                    Button { vm.start() } label: { Label(L("Atualizar"), systemImage: "arrow.clockwise") }
                }
            }
        }
        .sheet(item: $selected) { TorrentActionsSheet(torrent: $0).environmentObject(app) }
        .sheet(isPresented: $showErrors) { SearchErrorsSheet(errors: vm.results.errors) }
        .sheet(isPresented: $showProviderFilter) {
            ProviderFilterSheet(all: vm.providerNames, excluded: $vm.excludedProviders)
        }
        .task { if vm.results.totalProviders == 0 { vm.start() } }
        .onDisappear { vm.stop() }
    }

    private var filtersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Toggle(isOn: $vm.showDead) { Text(L("Sem fontes")) }.toggleStyle(.button)
                Toggle(isOn: $vm.hideViewed) { Text(L("Ocultar vistos")) }.toggleStyle(.button)
                Button { showProviderFilter = true } label: {
                    Label(vm.excludedProviders.isEmpty ? L("Buscadores") : L("Buscadores (%ld)", vm.providerNames.count - vm.excludedProviders.count),
                          systemImage: "line.3.horizontal.decrease.circle")
                }.buttonStyle(.bordered)
                if vm.category == .all {
                    Menu {
                        Picker(L("Categoria"), selection: $vm.categoryFilter) {
                            ForEach(app.visibleCategories) { Text($0.title).tag($0) }
                        }
                    } label: { Label(vm.categoryFilter.title, systemImage: vm.categoryFilter.systemImage) }
                    .buttonStyle(.bordered)
                }
            }
            .font(.subheadline)
            .padding(.horizontal).padding(.vertical, 6)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker(L("Ordenar por"), selection: $vm.sort.criteria) {
                ForEach(SortCriteria.allCases) { Text($0.title).tag($0) }
            }
            Picker(L("Ordem"), selection: $vm.sort.order) {
                ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
            }
        } label: { Label(L("Ordenar"), systemImage: "arrow.up.arrow.down") }
    }

    @ViewBuilder private func contextMenu(_ t: Torrent) -> some View {
        if case .available(let m) = t.magnetUri {
            Button { MagnetOpener.copy(m); Toast.shared.show(L("Link magnet copiado!")) } label: { Label(L("Copiar link magnet"), systemImage: "doc.on.doc") }
        }
        Button { app.toggleBookmark(t) } label: {
            Label(app.isBookmarked(t) ? L("Remover dos favoritos") : L("Adicionar aos favoritos"), systemImage: "bookmark")
        }
    }
}

struct SearchErrorsSheet: View {
    let errors: [SearchProviderError]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(errors) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.providerName).font(.headline)
                    Text(e.kind == .cloudflareChallenge ? L("Bloqueado pelo Cloudflare — desbloqueie em Ajustes → Buscadores") : L("Falhou"))
                        .font(.subheadline).foregroundStyle(e.kind == .cloudflareChallenge ? .orange : .red)
                    Text(e.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .navigationTitle(L("Buscadores com falha"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("OK")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ProviderFilterSheet: View {
    let all: [String]
    @Binding var excluded: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(all, id: \.self) { name in
                Button {
                    if excluded.contains(name) { excluded.remove(name) } else { excluded.insert(name) }
                } label: {
                    HStack {
                        Text(name).foregroundStyle(.primary)
                        Spacer()
                        if !excluded.contains(name) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
            .navigationTitle(L("Filtrar por buscador"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("OK")) { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button(L("Todos")) { excluded = [] }
                        Spacer()
                        Button(L("Nenhum")) { excluded = Set(all) }
                        Spacer()
                        Button(L("Inverter")) { excluded = Set(all).subtracting(excluded) }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
