import Foundation
import SwiftUI
import Security

/// Estado global do app: ajustes, favoritos, histórico, buscadores.
/// Tudo fica só no aparelho (Application Support com proteção de arquivo; chave de API no Keychain).
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum DarkTheme: String, CaseIterable, Identifiable {
        case system, on, off
        var id: String { rawValue }
        var title: String { self == .system ? L("Seguir o sistema") : self == .on ? L("Ativado") : L("Desativado") }
        var scheme: ColorScheme? { self == .system ? nil : self == .on ? .dark : .light }
    }

    /// Suíte própria: não mistura com os ajustes do iTorrent.
    private let d = UserDefaults(suiteName: "com.glauber.superapp.busca") ?? .standard

    // MARK: Ajustes (mesmos padrões do app original)
    @Published var darkTheme: DarkTheme { didSet { d.set(darkTheme.rawValue, forKey: "dark_theme") } }
    @Published var nsfwMode: Bool { didSet { d.set(nsfwMode, forKey: "enable_nsfw_mode"); if !nsfwMode { disableUnsafeProviders() } } }
    @Published var saveSearchHistory: Bool { didSet { d.set(saveSearchHistory, forKey: "save_search_history") } }
    @Published var showSearchHistory: Bool { didSet { d.set(showSearchHistory, forKey: "show_search_history") } }
    @Published var showRecentSearches: Bool { didSet { d.set(showRecentSearches, forKey: "show_recent_searches") } }
    @Published var checkProvidersOnStartup: Bool { didSet { d.set(checkProvidersOnStartup, forKey: "check_providers_on_startup") } }
    @Published var defaultSort: SortOptions { didSet { save(defaultSort, "default_sort") } }
    @Published var bookmarksSort: SortOptions { didSet { save(bookmarksSort, "bookmarks_sort") } }
    /// nil = ilimitado
    @Published var maxNumResults: Int? { didSet { d.set(maxNumResults ?? -1, forKey: "max_num_results") } }

    // MARK: Buscadores
    /// nil = primeira execução (o app pergunta se quer ativar os recomendados).
    @Published var enabledProviderIds: Set<String>? { didSet { d.set(enabledProviderIds.map(Array.init), forKey: "enabled_search_providers_id") } }
    @Published var unlockedProviderIds: Set<String> { didSet { d.set(Array(unlockedProviderIds), forKey: "protection_unlocked_provider_ids") } }
    @Published var torznabConfigs: [TorznabConfig] = [] { didSet { persistTorznab() } }

    // MARK: Dados do usuário
    @Published var bookmarks: [Bookmark] = [] { didSet { Self.write(bookmarks, "bookmarks.json") } }
    @Published var history: [SearchHistoryItem] = [] { didSet { Self.write(history, "search_history.json") } }
    @Published var viewedIds: Set<String> = [] { didSet { Self.write(Array(viewedIds), "viewed.json") } }

    let builtin: [SearchProvider] = ProviderRegistry.builtin

    private init() {
        darkTheme = DarkTheme(rawValue: d.string(forKey: "dark_theme") ?? "") ?? .system
        nsfwMode = d.object(forKey: "enable_nsfw_mode") as? Bool ?? false
        saveSearchHistory = d.object(forKey: "save_search_history") as? Bool ?? true
        showSearchHistory = d.object(forKey: "show_search_history") as? Bool ?? true
        showRecentSearches = d.object(forKey: "show_recent_searches") as? Bool ?? false
        checkProvidersOnStartup = d.object(forKey: "check_providers_on_startup") as? Bool ?? true
        defaultSort = Self.load(SortOptions.self, "default_sort", d) ?? SortOptions()
        bookmarksSort = Self.load(SortOptions.self, "bookmarks_sort", d) ?? SortOptions(criteria: .date, order: .descending)
        let m = d.object(forKey: "max_num_results") as? Int ?? -1
        maxNumResults = m < 0 ? nil : m
        enabledProviderIds = (d.array(forKey: "enabled_search_providers_id") as? [String]).map(Set.init)
        unlockedProviderIds = Set(d.array(forKey: "protection_unlocked_provider_ids") as? [String] ?? [])
        bookmarks = Self.read([Bookmark].self, "bookmarks.json") ?? []
        history = Self.read([SearchHistoryItem].self, "search_history.json") ?? []
        viewedIds = Set(Self.read([String].self, "viewed.json") ?? [])
        torznabConfigs = (Self.read([TorznabConfig].self, "torznab.json") ?? []).map { c in
            var c = c; c.apiKey = Keychain.get("torznab.\(c.id)") ?? ""; return c
        }
    }

    // MARK: Buscadores

    var allProviders: [SearchProvider] { builtin + torznabConfigs.map { TorznabSearchProvider(config: $0) } }

    func isEnabled(_ id: String) -> Bool { enabledProviderIds?.contains(id) ?? false }

    func protection(_ p: SearchProvider) -> CloudflareProtectionStatus {
        !p.isCloudflareProtected ? .unprotected : unlockedProviderIds.contains(p.id) ? .unlocked : .locked
    }

    /// Buscadores ativos, filtrados pela categoria e pelo modo NSFW.
    func enabledProviders(category: Category = .all) -> [SearchProvider] {
        allProviders.filter { isEnabled($0.id) }
            .filter { category == .all || $0.supportedCategories.contains(category) }
    }

    func setEnabled(_ id: String, _ on: Bool) {
        var s = enabledProviderIds ?? []
        if on { s.insert(id) } else { s.remove(id) }
        enabledProviderIds = s
    }

    func isNSFWProvider(_ p: SearchProvider) -> Bool {
        p.supportedCategories.contains { $0.isNSFW } || p.safety.isUnsafe
    }

    /// Ativa o conjunto recomendado (igual ao original: padrão e sem Cloudflare).
    func enableDefaultProviders() {
        enabledProviderIds = Set(builtin.filter { $0.enabledByDefault && !$0.isCloudflareProtected }.map(\.id))
    }

    func skipDefaultProviders() { enabledProviderIds = [] }

    func enableAll(_ ids: [String]) {
        let allowed = allProviders.filter { ids.contains($0.id) }
            .filter { !$0.isCloudflareProtected || unlockedProviderIds.contains($0.id) }
        enabledProviderIds = (enabledProviderIds ?? []).union(allowed.map(\.id))
    }

    func disableAll(_ ids: [String]) { enabledProviderIds = (enabledProviderIds ?? []).subtracting(ids) }

    func disableUnsafeProviders() {
        let unsafe = allProviders.filter(isNSFWProvider).map(\.id)
        if let e = enabledProviderIds { enabledProviderIds = e.subtracting(unsafe) }
    }

    func lockProvider(_ id: String) {
        unlockedProviderIds.remove(id)
        if let p = builtin.first(where: { $0.id == id }) { Net.removeCookies(for: p.cloudflareSolverUrl ?? p.url) }
        setEnabled(id, false)
    }

    func unlockProvider(_ id: String) { unlockedProviderIds.insert(id) }

    func resetProvidersToDefault() {
        unlockedProviderIds = []
        Net.removeAllCookies()
        CloudflareCookies.clearWebViewData()
        enableDefaultProviders()
    }

    /// Verifica quais buscadores protegidos continuam liberados (como no original).
    func updateProtectionStatus() async -> (locked: Int, unlocked: Int)? {
        let protected = builtin.filter(\.isCloudflareProtected)
        var locked = 0, failed = 0
        for p in protected {
            let u = p.cloudflareSolverUrl ?? p.url
            guard let challenged = try? await Net.shared.isUrlChallenged(u) else { failed += 1; continue }
            if challenged { lockProvider(p.id); locked += 1 } else { unlockProvider(p.id) }
        }
        if failed == protected.count { return nil }
        return (locked, protected.count - locked)
    }

    // MARK: Torznab

    func saveTorznab(_ c: TorznabConfig) {
        if let i = torznabConfigs.firstIndex(where: { $0.id == c.id }) { torznabConfigs[i] = c } else { torznabConfigs.append(c) }
    }

    func deleteTorznab(_ id: String) {
        torznabConfigs.removeAll { $0.id == id }
        Keychain.delete("torznab.\(id)")
        setEnabled(id, false)
    }

    private func persistTorznab() {
        for c in torznabConfigs { Keychain.set(c.apiKey, for: "torznab.\(c.id)") }
        // A chave de API não vai para o arquivo; fica só no Keychain.
        Self.write(torznabConfigs.map { var c = $0; c.apiKey = ""; return c }, "torznab.json")
    }

    // MARK: Histórico, favoritos, vistos

    func recordSearch(_ q: String) {
        guard saveSearchHistory else { return }
        let t = q.trimmed
        guard !t.isEmpty else { return }
        history.removeAll { $0.query.caseInsensitiveCompare(t) == .orderedSame }
        history.insert(SearchHistoryItem(query: t, date: Date()), at: 0)
        if history.count > 500 { history.removeLast(history.count - 500) }
    }

    var recentSearches: [SearchHistoryItem] { Array(history.prefix(5)) }

    func isBookmarked(_ t: Torrent) -> Bool { bookmarks.contains { $0.torrent.id == t.id } }

    func toggleBookmark(_ t: Torrent) {
        if isBookmarked(t) { bookmarks.removeAll { $0.torrent.id == t.id } }
        else { bookmarks.insert(Bookmark(torrent: t, addedAt: Date()), at: 0) }
    }

    func markViewed(_ t: Torrent) { if !viewedIds.contains(t.id) { viewedIds.insert(t.id) } }

    /// Apaga todos os dados guardados pelo app.
    func eraseAllData() {
        bookmarks = []; history = []; viewedIds = []
        for c in torznabConfigs { Keychain.delete("torznab.\(c.id)") }
        torznabConfigs = []
        unlockedProviderIds = []
        Net.removeAllCookies()
        CloudflareCookies.clearWebViewData()
        URLCache.shared.removeAllCachedResponses()
        enabledProviderIds = nil
    }

    // MARK: Persistência

    private func save<T: Encodable>(_ v: T, _ key: String) { d.set(try? JSONEncoder().encode(v), forKey: key) }
    private static func load<T: Decodable>(_ t: T.Type, _ key: String, _ d: UserDefaults) -> T? {
        (d.data(forKey: key)).flatMap { try? JSONDecoder().decode(t, from: $0) }
    }

    static var dataDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TorrentSearch", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func write<T: Encodable>(_ v: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(v) else { return }
        // Arquivo criptografado pelo iOS enquanto o aparelho estiver bloqueado.
        try? data.write(to: dataDir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
    }

    static func read<T: Decodable>(_ t: T.Type, _ name: String) -> T? {
        (try? Data(contentsOf: dataDir.appendingPathComponent(name))).flatMap { try? JSONDecoder().decode(t, from: $0) }
    }
}

/// Acesso mínimo ao Keychain (para a chave de API do Torznab).
enum Keychain {
    private static let service = "SuperApp.Busca"

    static func set(_ value: String, for key: String) {
        delete(key)
        guard !value.isEmpty else { return }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}
