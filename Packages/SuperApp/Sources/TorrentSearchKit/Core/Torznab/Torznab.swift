import Foundation
import SwiftSoup
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Buscador Torznab (Jackett, Prowlarr etc.) configurado pelo usuário.
final class TorznabSearchProvider: SearchProvider {
    let config: TorznabConfig
    var id: String { config.id }
    var name: String { config.searchProviderName }
    var url: String { config.url }
    var supportedCategories: Set<Category> { config.supportedCategories }
    let enabledByDefault = false

    init(config: TorznabConfig) { self.config = config }

    func search(query: String, category: Category) async throws -> [Torrent] {
        var u = "\(TorznabUtils.normalizeApiUrl(config.url))?apikey=\(config.apiKey.uriEncoded)&extended=1&t=search&q=\(query)"
        if category != .all, config.supportedCategories.contains(category), let cats = TorznabCategoryMapper.catParam(category) {
            u += "&cat=\(cats)"
        }
        return TorznabResultsParser.parse(try await net.getText(u), providerId: id, providerName: name)
    }
}

enum TorznabCategoryMapper {
    static let categoryToIds: [Category: [Int]] = [
        .anime: [5070],
        .apps: [4000, 4010, 4020, 4030, 4040, 4050, 4060, 4070],
        .books: [7000, 7010, 7020, 7030, 7040, 7050, 7060],
        .games: [1000, 4050],
        .movies: [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080],
        .music: [3000, 3010, 3040, 3050, 3060],
        .porn: [6000, 6010, 6020, 6030, 6040, 6045, 6050, 6060, 6070, 6080, 6090],
        .series: [5000, 5010, 5020, 5030, 5040, 5045, 5050, 5060, 5080],
        .other: [8000, 8010, 8020],
    ]
    static func catParam(_ c: Category) -> String? {
        // O original usa joinToString() (", "); codificado para URL.
        categoryToIds[c].map { $0.map(String.init).joined(separator: ",%20") }
    }
    static func category(_ id: Int) -> Category {
        switch id {
        case 1000...1999: return .games
        case 2000...2999: return .movies
        case 3000...3999: return id == 3030 ? .books : .music
        case 4000...4999: return id == 4050 ? .games : .apps
        case 5000...5999: return id == 5070 ? .anime : .series
        case 6000...6999: return .porn
        case 7000...7999: return .books
        default: return .other
        }
    }
}

enum TorznabResultsParser {
    static func parse(_ xml: String, providerId: String, providerName: String) -> [Torrent] {
        guard let doc = Html.parseXml(xml) else { return [] }
        return doc.all("item").compactMap { item -> Torrent? in
            var title: String?, size: String?, seeders: String?, peers: String?, date: Date?
            var details: String?, magnet: String?, hash: String?, file: String?
            var cats = Set<Int>()
            for c in item.kids {
                switch c.tagName() {
                case "title": title = c.txt
                case "comments": details = c.txt
                case "pubDate": date = TorrentDateParser.parseRFC1123(c.txt)
                case "size": size = FileSizeUtils.formatBytes(c.txt)
                case "enclosure":
                    if file == nil, c.at("type") == "application/x-bittorrent", !c.at("url").hasPrefix("magnet:?") { file = c.at("url").nonBlank }
                case "torznab:attr":
                    let v = c.at("value")
                    switch c.at("name") {
                    case "seeders": seeders = v
                    case "peers": peers = v
                    case "magneturl": magnet = v
                    case "infohash": hash = v
                    case "category": if let i = Int(v), i < 100000 { cats.insert(i) }
                    case "size": if size == nil { size = FileSizeUtils.formatBytes(v) }
                    default: break
                    }
                default: break
                }
            }
            guard let title, let hash, let magnet else { return nil }
            return Torrent(id: TorrentUtils.createTorrentId(providerId: providerId, sourceId: hash), name: title, size: size,
                           seeders: seeders?.uint, peers: peers?.uint, providerName: providerName, uploadDate: date,
                           category: cats.max().map(TorznabCategoryMapper.category) ?? .other, detailsPageUrl: details,
                           magnetUri: .available(magnet), fileDownloadLink: file)
        }
    }
}

enum TorznabConnectionResult: Equatable {
    case established, connectionFailed, invalidApiKey, applicationError(Int), unexpectedResponse(Int), unexpectedError

    var message: String {
        switch self {
        case .established: return L("Conexão estabelecida")
        case .connectionFailed: return L("Não foi possível conectar ao servidor")
        case .invalidApiKey: return L("Chave de API inválida")
        case .applicationError(let c): return L("Erro do indexador (código %ld)", c)
        case .unexpectedResponse(let c): return L("Resposta inesperada (código %ld)", c)
        case .unexpectedError: return L("Erro inesperado")
        }
    }
}

enum TorznabUtils {
    static func normalizeApiUrl(_ url: String) -> String {
        var u = url
        while u.hasSuffix("/") { u.removeLast() }
        return u.hasSuffix("api") ? u : "\(u)/api"
    }

    static func supportedCategories(apiUrl: String, apiKey: String) async throws -> Set<Category>? {
        let xml = try await Net.shared.getText("\(normalizeApiUrl(apiUrl))?t=caps&apikey=\(apiKey.uriEncoded)")
        guard let doc = Html.parseXml(xml) else { return nil }
        var set = Set<Category>()
        for c in doc.all("caps > categories > category") {
            if let id = Int(c.at("id")), id < 100000 { set.insert(TorznabCategoryMapper.category(id)) }
        }
        return set
    }

    static func checkConnection(apiUrl: String, apiKey: String) async -> TorznabConnectionResult {
        let resp: Net.Response
        do {
            resp = try await Net.shared.get("\(normalizeApiUrl(apiUrl))?t=caps&apikey=\(apiKey.uriEncoded)")
        } catch is CloudflareChallengeError {
            return .unexpectedError
        } catch {
            return .connectionFailed
        }
        if resp.status == 401 { return .invalidApiKey }
        guard resp.status == 200 else { return .unexpectedError }
        let body = resp.text.removingPrefix(#"<?xml version="1.0" encoding="UTF-8"?>"#).trimmed
        if body.hasPrefix("<caps>") { return .established }
        guard body.hasPrefix("<error code="), let code = body.firstMatch(#"code="(\d+)""#).flatMap({ Int($0) }) else {
            return .unexpectedError
        }
        switch code {
        case 100...199: return .invalidApiKey
        case 200...299: return .applicationError(code)
        default: return .unexpectedResponse(code)
        }
    }
}
