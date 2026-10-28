import Foundation

/// Resultado acumulado de uma busca em vários buscadores.
struct SearchResults {
    var torrents: [Torrent] = []
    var errors: [SearchProviderError] = []
    var finishedProviders = 0
    var totalProviders = 0
    var isComplete: Bool { finishedProviders >= totalProviders }
}

/// Equivale ao TorrentQueryService.kt: busca em paralelo e vai entregando os resultados.
enum SearchService {
    /// Busca em todos os buscadores informados, emitindo o acumulado a cada buscador concluído.
    /// - Parameter limit: número máximo de resultados (nil = ilimitado).
    /// - Parameter onCloudflare: chamado quando um buscador é bloqueado pelo Cloudflare.
    static func search(query: String, category: Category, providers: [SearchProvider], limit: Int?,
                       onCloudflare: @escaping @Sendable (String) -> Void = { _ in }) -> AsyncStream<SearchResults> {
        let encoded = query.uriEncoded
        return run(providers: providers, limit: limit, onCloudflare: onCloudflare) { p in
            try await p.search(query: encoded, category: category)
        }
    }

    static func latest(category: Category, providers: [SearchProvider]) -> AsyncStream<SearchResults> {
        let ps = providers.compactMap { $0 as? LatestTorrentsProvider }
            .filter { category == .all || $0.supportedCategories.contains(category) }
        return run(providers: ps, limit: nil) { p in try await (p as! LatestTorrentsProvider).getLatestTorrents(category: category) }
    }

    static func top(category: Category, providers: [SearchProvider]) -> AsyncStream<SearchResults> {
        let ps = providers.compactMap { $0 as? TopTorrentsProvider }
            .filter { category == .all || $0.supportedCategories.contains(category) }
        return run(providers: ps, limit: nil) { p in try await (p as! TopTorrentsProvider).getTopTorrents(category: category) }
    }

    private static func run(providers: [SearchProvider], limit: Int?,
                            onCloudflare: @escaping @Sendable (String) -> Void = { _ in },
                            _ action: @escaping (SearchProvider) async throws -> [Torrent]) -> AsyncStream<SearchResults> {
        AsyncStream { continuation in
            let task = Task {
                var acc = SearchResults(totalProviders: providers.count)
                if providers.isEmpty { continuation.yield(acc); continuation.finish(); return }
                continuation.yield(acc)
                await withTaskGroup(of: (SearchProvider, Result<[Torrent], Error>).self) { group in
                    for p in providers {
                        group.addTask {
                            do { return (p, .success(try await action(p))) } catch { return (p, .failure(error)) }
                        }
                    }
                    for await (p, result) in group {
                        if Task.isCancelled { break }
                        acc.finishedProviders += 1
                        switch result {
                        case .success(let list): acc.torrents.append(contentsOf: list)
                        case .failure(let error):
                            if error is CancellationError { continue }
                            let cf = error is CloudflareChallengeError
                            if cf { onCloudflare(p.id) }
                            acc.errors.append(SearchProviderError(
                                providerId: p.id, providerName: p.name, providerUrl: p.url,
                                kind: cf ? .cloudflareChallenge : .crash, message: describe(error)))
                        }
                        if let limit, acc.torrents.count >= limit {
                            acc.torrents = Array(acc.torrents.prefix(limit))
                            acc.finishedProviders = acc.totalProviders
                            continuation.yield(acc)
                            group.cancelAll()
                            break
                        }
                        continuation.yield(acc)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        if let u = error as? URLError {
            switch u.code {
            case .timedOut: return L("Tempo esgotado")
            case .notConnectedToInternet: return L("Sem conexão com a internet")
            case .cannotFindHost, .dnsLookupFailed: return L("Site não encontrado (pode estar bloqueado pela sua operadora)")
            case .secureConnectionFailed, .serverCertificateUntrusted: return L("Falha na conexão segura")
            default: return u.localizedDescription
            }
        }
        return String(describing: error)
    }

    /// Ordenação igual ao SortUtils.kt (valores ausentes contam como menores).
    static func sort(_ list: [Torrent], by o: SortOptions) -> [Torrent] {
        func cmp<T: Comparable>(_ a: T?, _ b: T?) -> Bool {
            switch (a, b) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?): return x < y
            }
        }
        let asc: (Torrent, Torrent) -> Bool
        switch o.criteria {
        case .name: asc = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .seeders: asc = { cmp($0.seeders, $1.seeders) }
        case .peers: asc = { cmp($0.peers, $1.peers) }
        case .fileSize: asc = { cmp($0.size.map(FileSizeUtils.getBytes), $1.size.map(FileSizeUtils.getBytes)) }
        case .date: asc = { cmp($0.uploadDate, $1.uploadDate) }
        }
        // sort estável: mantém a ordem original entre iguais
        let indexed = Array(list.enumerated())
        let sorted = indexed.sorted { a, b in
            let lt = o.order == .ascending ? asc(a.element, b.element) : asc(b.element, a.element)
            let gt = o.order == .ascending ? asc(b.element, a.element) : asc(a.element, b.element)
            if lt { return true }
            if gt { return false }
            return a.offset < b.offset
        }
        return sorted.map(\.element)
    }

    /// Filtro de texto igual ao TorrentFilters.matchesQuery (qualquer palavra).
    static func matches(_ t: Torrent, query: String) -> Bool {
        let words = query.split(separator: " ").map(String.init).filter { !$0.trimmed.isEmpty }
        if words.isEmpty { return true }
        return words.contains { t.name.localizedCaseInsensitiveContains($0) }
    }
}

/// Download do arquivo .torrent (equivale ao TorrentFileDownloader.kt).
enum TorrentFileDownloader {
    enum Result { case success(Data), failed, notFound }

    /// Usa o itorrents.net com o info hash (só quando o usuário pede).
    static func downloadUsingInfoHash(_ hash: String) async -> Result {
        await download("https://itorrents.net/torrent/\(hash.uppercased()).torrent")
    }

    static func download(_ url: String) async -> Result {
        do {
            let r = try await Net.shared.get(url)
            guard r.isSuccess, !r.data.isEmpty else { return .notFound }
            return .success(r.data)
        } catch { return .failed }
    }
}
