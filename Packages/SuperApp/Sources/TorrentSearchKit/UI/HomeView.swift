import SwiftUI

enum HomeSheet: String, Identifiable { case browse, bookmarks, settings; var id: String { rawValue } }

struct SearchRoute: Hashable { let query: String; let category: Category }

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var category: Category = .all
    @State private var path = NavigationPath()
    @State private var message: String?
    @FocusState private var focused: Bool
    @State private var sheet: HomeSheet?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 64)).foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Torrent Search").font(.largeTitle.bold())
                        Text(L("Busca em vários sites ao mesmo tempo, sem anúncios e sem rastreamento."))
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 24).padding(.horizontal)

                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(L("Buscar…"), text: $query)
                            .focused($focused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit(search)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .accessibilityLabel(L("Limpar"))
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    CategoryChips(selection: $category, categories: app.visibleCategories)

                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }

                    Button(action: search) {
                        Label(L("Buscar"), systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .padding(.horizontal)

                    if focused && app.showSearchHistory && !app.history.isEmpty {
                        suggestions
                    } else if app.showRecentSearches && !app.recentSearches.isEmpty {
                        recent
                    }

                    Text(L("%ld de %ld buscadores ativos", app.enabledProviders().count, app.allProviders.count))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(for: SearchRoute.self) { SearchView(query: $0.query, category: $0.category) }
            .onChange(of: app.nsfwMode) { _ in if !app.nsfwMode && category.isNSFW { category = .all } }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { sheet = .browse } label: { Image(systemName: "sparkles") }.accessibilityLabel(L("Explorar"))
                    Button { sheet = .bookmarks } label: { Image(systemName: "bookmark") }.accessibilityLabel(L("Favoritos"))
                    Button { sheet = .settings } label: { Image(systemName: "gearshape") }.accessibilityLabel(L("Ajustes"))
                }
            }
            .sheet(item: $sheet) { s in
                Group {
                    switch s {
                    case .browse: BrowseView(showsClose: true)
                    case .bookmarks: BookmarksView(showsClose: true)
                    case .settings: SettingsView(showsClose: true)
                    }
                }
                .environmentObject(app)
                .toastOverlay()
            }
        }
    }

    private var suggestions: some View {
        let matches = app.history.filter { query.isEmpty || $0.query.localizedCaseInsensitiveContains(query) }.prefix(6)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(matches)) { h in
                Button { query = h.query; search() } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                        Text(h.query).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.left").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10).padding(.horizontal)
                }
                Divider().padding(.leading)
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Buscas recentes")).font(.headline).padding(.horizontal)
            FlowChips(items: app.recentSearches.map(\.query)) { q in query = q; search() }
                .padding(.horizontal)
        }
    }

    private func search() {
        let q = query.trimmed
        message = nil
        guard !q.isEmpty else { message = L("Digite algo para buscar"); return }
        if let u = URL(string: q), u.scheme == "http" || u.scheme == "https" { message = L("Não é possível buscar usando uma URL"); return }
        focused = false
        app.recordSearch(q)
        path.append(SearchRoute(query: q, category: category))
    }
}

/// Lista de “chips” que quebra linha.
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(items, id: \.self) { s in
                    Button(s) { onTap(s) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
            }
        }
    }
}
