import Foundation

/// Buscador de torrents (equivale à interface `SearchProvider` do original).
protocol SearchProvider: AnyObject {
    var id: String { get }
    var name: String { get }
    var url: String { get }
    /// URL usada para resolver o desafio do Cloudflare (nil = usa `url`).
    var cloudflareSolverUrl: String? { get }
    var supportedCategories: Set<Category> { get }
    var safety: ProviderSafety { get }
    var isCloudflareProtected: Bool { get }
    var enabledByDefault: Bool { get }
    /// `query` já chega codificada para URL.
    func search(query: String, category: Category) async throws -> [Torrent]
}

extension SearchProvider {
    var cloudflareSolverUrl: String? { nil }
    var safety: ProviderSafety { .safe }
    var isCloudflareProtected: Bool { false }
    var net: Net { Net.shared }

    func torrentId(_ sourceId: String) -> String {
        TorrentUtils.createTorrentId(providerId: id, sourceId: sourceId)
    }
}

/// Buscador que precisa abrir outra página para obter o link magnet.
protocol MagnetUriProvider: SearchProvider {
    func getMagnetUri(url: String) async throws -> String
}

/// Buscador que lista os torrents mais recentes.
protocol LatestTorrentsProvider: SearchProvider {
    func getLatestTorrents(category: Category) async throws -> [Torrent]
}

/// Buscador que lista os torrents em alta.
protocol TopTorrentsProvider: SearchProvider {
    func getTopTorrents(category: Category) async throws -> [Torrent]
}

struct ProviderParseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Executa tarefas em paralelo e junta os resultados (equivale a async/awaitAll).
func concurrentMap<T, R>(_ items: [T], _ transform: @escaping (T) async throws -> R) async rethrows -> [R] {
    try await withThrowingTaskGroup(of: (Int, R).self) { group in
        for (i, item) in items.enumerated() {
            group.addTask { (i, try await transform(item)) }
        }
        var out = [(Int, R)]()
        for try await r in group { out.append(r) }
        return out.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}

/// Igual ao anterior, mas ignora as tarefas que falharem.
func concurrentMapIgnoringErrors<T, R>(_ items: [T], _ transform: @escaping (T) async throws -> R) async -> [R] {
    await withTaskGroup(of: (Int, R?).self) { group in
        for (i, item) in items.enumerated() {
            group.addTask { (i, try? await transform(item)) }
        }
        var out = [(Int, R)]()
        for await (i, r) in group { if let r { out.append((i, r)) } }
        return out.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}
