import Foundation
import SwiftSoup
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Portado de: Ext, Eztv, FileMood, FitGirlRepacks, InternetArchive, Knaben.

// MARK: Ext
final class Ext: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "extdotto", name = "Ext", url = "https://ext.to"
    var cloudflareSolverUrl: String? { "\(url)/browse/?q=ubuntu" }
    let supportedCategories: Set<Category> = [.anime, .apps, .books, .games, .movies, .music, .other, .porn, .series]
    let enabledByDefault = false
    let isCloudflareProtected = true
    private let categoryMap: [Category: Int] = [.anime: 7, .apps: 5, .books: 6, .games: 4, .movies: 1, .music: 3, .other: 8, .porn: 10, .series: 2]

    func search(query: String, category: Category) async throws -> [Torrent] {
        var u = "\(url)/browse/?"
        if let c = categoryMap[category] { u += "cat=\(c)&" }
        u += "q=\(query)"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] { try await browse("age", category) }
    func getTopTorrents(category: Category) async throws -> [Torrent] { try await browse("seeds", category) }
    private func browse(_ sort: String, _ category: Category) async throws -> [Torrent] {
        var u = "\(url)/browse/?sort=\(sort)&order=desc&age=4"
        if category != .all, let c = categoryMap[category] { u += "&cat=\(c)" }
        return parse(try await net.getText(u), u)
    }

    func getMagnetUri(url: String) async throws -> String {
        let doc = Html.parse(try await net.getText(url))
        guard let tid = doc?.first("a.detail-magnet-link.download-btn-magnet")?.at("data-id").nonBlank,
              let sess = doc?.first(#"meta[name="csrf-token"]"#)?.at("content").nonBlank,
              let token = doc?.all("script").compactMap({ $0.dataText.trimmed.lines.first })
                .first(where: { $0.hasPrefix("window.pageToken") })?
                .removingSuffix("';").takeLastWhile({ $0 != "'" }) else {
            throw ProviderParseError(message: "Token do Ext não encontrado")
        }
        let ts = Int64(Date().timeIntervalSince1970)
        let hmac = SHA256.hash(data: Data("\(tid)|\(ts)|\(token)".utf8)).map { String(format: "%02x", $0) }.joined()
        let resp = try await net.submitForm("https://ext.to/ajax/getTorrentMagnet.php", form: [
            ("torrent_id", tid), ("download_type", "magnet"), ("timestamp", String(ts)), ("hmac", hmac), ("sessid", sess),
        ])
        guard let obj = try? JSONSerialization.jsonObject(with: Data(resp.utf8)) as? JObj, let m = obj.str("url") else {
            throw ProviderParseError(message: "Magnet não encontrado")
        }
        return m
    }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        let nameSel = "td:nth-child(1) > div:nth-child(1) > a.torrent-title-link"
        return (Html.parse(html, baseUrl: pageUrl)?.all("table.search-table > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first(nameSel), let details = a.at("abs:href").nonBlank,
                  let rid = li.first("td:nth-child(1) > div:nth-child(2) > a.search-magnet-btn")?.at("data-id") else { return nil }
            let cat = li.first("td:nth-child(1) > div:nth-child(1) > div.related-posted > a:nth-child(2)").attrStr("href")
                .map { $0.removingSurrounding("/", "/") }
            return Torrent(id: torrentId(rid), name: a.txt, size: li.first("td:nth-child(2) > div > span:nth-child(2)").ownStr,
                           seeders: li.first("td:nth-child(5) > div > span:nth-child(2)")?.own.uint,
                           peers: li.first("td:nth-child(6) > div > span:nth-child(2)")?.own.uint, providerName: name,
                           uploadDate: li.first("td:nth-child(4) > div > span:nth-child(2)").attrStr("title")
                               .flatMap { TorrentDateParser.parse($0, format: "dd MMMM yyyy") },
                           category: cat.map(Self.category), detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
    static func category(_ raw: String) -> Category {
        switch raw {
        case "anime": return .anime
        case "applications": return .apps
        case "books": return .books
        case "games": return .games
        case "movies": return .movies
        case "music": return .music
        case "tv": return .series
        case "xxx": return .porn
        default: return .other
        }
    }
}

// MARK: Eztv
final class Eztv: SearchProvider {
    let id = "eztvx", name = "Eztv", url = "https://eztvx.to"
    var cloudflareSolverUrl: String? { "\(url)/home" }
    let supportedCategories: Set<Category> = [.series]
    let isCloudflareProtected = true
    let enabledByDefault = true

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search/\(query)"
        let html = try await net.getText(u, headers: ["Cookie": "layout=def_wlinks"])
        return (Html.parse(html, baseUrl: u)?.all("table:last-of-type > tbody > tr") ?? []).dropFirst(2).compactMap { li -> Torrent? in
            guard let a = li.first("td:nth-child(2) > a.epinfo"),
                  let magnet = li.first("td:nth-child(3) > a.magnet")?.at("href"),
                  let hash = TorrentUtils.infoHash(magnet) else { return nil }
            return Torrent(id: torrentId(hash), name: a.own, size: li.first("td:nth-child(4)").ownStr,
                           seeders: li.first("td:nth-child(6)")?.own.uint, peers: 0, providerName: name, category: .series,
                           detailsPageUrl: a.at("abs:href"), magnetUri: .available(magnet),
                           fileDownloadLink: li.first("td:nth-child(3) > a:nth-child(2)")?.at("abs:href"))
        }
    }
}

// MARK: FileMood
final class FileMood: SearchProvider {
    let id = "filemood", name = "FileMood", url = "https://filemood.com"
    let supportedCategories: Set<Category> = [.other]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/result?q=\(query)+in%3Atitle"
        return (Html.parse(try await net.getText(u), baseUrl: u)?.all("table > tbody > tr:has(a.btn-success)") ?? []).compactMap { li -> Torrent? in
            guard let tname = li.first("> td.dn-title")?.txt,
                  let details = li.first("td.dn-btn > div > a")?.at("abs:href").nonBlank else { return nil }
            let hash = details.removingSuffix(".html").takeLastWhile { $0 != "-" }.lowercased().trimmed
            let sp = li.first("td.dn-status")?.txt.split(separator: "/").map(String.init)
            return Torrent(id: torrentId(hash), name: tname, size: li.first("td.dn-size").textStr,
                           seeders: sp?[safe: 0]?.trimmed.uint, peers: sp?[safe: 1]?.trimmed.uint, providerName: name,
                           category: .other, detailsPageUrl: details, magnetUri: .available(TorrentUtils.createMagnetUri(hash)))
        }
    }
}

// MARK: FitGirl Repacks
final class FitGirlRepacks: SearchProvider, LatestTorrentsProvider, MagnetUriProvider {
    let id = "fitgirlrepacks", name = "FitGirl Repacks", url = "https://fitgirl-repacks.site"
    let supportedCategories: Set<Category> = [.games]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/?s=\(query)"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] { parse(try await net.getText(url), url) }
    func getMagnetUri(url: String) async throws -> String {
        guard let m = Html.parse(try await net.getText(url))?.first(#"a[href^="magnet:?xt="]"#)?.at("href").nonBlank else {
            throw ProviderParseError(message: "Magnet não encontrado")
        }
        return m
    }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("article.category-lossless-repack") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("header > h1.entry-title > a"), let details = a.at("abs:href").nonBlank else { return nil }
            let magnet: MagnetUri = li.first(#"div.entry-content a[href^="magnet:?xt="]"#).attrStr("href").nonBlank
                .map { .available($0) } ?? .requiresFetch(details)
            return Torrent(id: torrentId(li.id().nonBlank ?? details), name: a.own, providerName: name,
                           uploadDate: li.first("header > div.entry-meta > span.entry-date > a > time").attrStr("datetime")
                               .flatMap(TorrentDateParser.parseIso),
                           category: .games, detailsPageUrl: details, magnetUri: magnet)
        }
    }
}

// MARK: InternetArchive
final class InternetArchive: SearchProvider {
    let id = "internetarchive", name = "InternetArchive", url = "https://archive.org"
    let supportedCategories: Set<Category> = [.apps, .books, .movies, .other]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        var u = "\(url)/advancedsearch.php?q=title:\(query)"
        if category != .all {
            let media: String
            switch category {
            case .apps: media = "software"
            case .books: media = "texts"
            case .movies: media = "movies"
            default: media = "other"
            }
            u += "%20AND%20mediatype:%28\(media)%29"
        }
        u += "&fl%5B%5D=title,item_size,publicdate,mediatype,identifier,btih&rows=100&page=1&output=json"
        let json = try await net.getJson(u) as? JObj
        return (json?.obj("response")?.objs("docs") ?? []).compactMap { o -> Torrent? in
            guard let title = o.str("title"), let hash = o.str("btih")?.lowercased().trimmed else { return nil }
            let rid = o.str("identifier")
            return Torrent(id: torrentId(rid ?? hash), name: title, size: o.double("item_size").map(FileSizeUtils.formatBytes),
                           providerName: name, uploadDate: o.str("publicdate").flatMap(TorrentDateParser.parseIso),
                           category: o.str("mediatype").map(Self.category),
                           detailsPageUrl: rid.map { "\(url)/details/\($0)" }, magnetUri: .available(TorrentUtils.createMagnetUri(hash)))
        }
    }
    static func category(_ m: String) -> Category {
        switch m {
        case "software": return .apps
        case "texts": return .books
        case "movies": return .movies
        default: return .other
        }
    }
}

// MARK: Knaben
final class Knaben: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "knaben", name = "Knaben", url = "https://knaben.org"
    let supportedCategories: Set<Category> = [.anime, .apps, .books, .games, .movies, .music, .other, .porn, .series]
    let enabledByDefault = true
    private let api = "https://api.knaben.org/v1"

    func search(query: String, category: Category) async throws -> [Torrent] {
        parse(try await net.postJson(api, payload: body(query, category, "seeders")))
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        parse(try await net.postJson(api, payload: body(nil, category, "date")))
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        parse(try await net.postJson(api, payload: body(nil, category, "seeders")))
    }
    private func body(_ query: String?, _ category: Category, _ orderBy: String) -> [String: Any] {
        var b: [String: Any] = ["size": 300, "order_by": orderBy, "order_direction": "desc", "hide_unsafe": true, "hide_xxx": false]
        if let query { b["query"] = query.uriDecoded }
        let ids: [Int]
        switch category {
        case .all: ids = []
        case .music: ids = [1000000]
        case .series: ids = [2000000]
        case .movies: ids = [3000000]
        case .apps: ids = [4000000]
        case .porn: ids = [5000000]
        case .anime: ids = [6000000]
        case .games: ids = [7000000]
        case .books: ids = [9000000]
        case .other: ids = [10000000]
        }
        if !ids.isEmpty { b["categories"] = ids }
        return b
    }
    private func parse(_ json: Any?) -> [Torrent] {
        ((json as? JObj)?.objs("hits") ?? []).compactMap { o -> Torrent? in
            guard let title = o.str("title"), let magnet = o.str("magnetUrl") else { return nil }
            let firstId = (o.arr("categoryId") ?? []).compactMap { ($0 as? NSNumber)?.int64Value ?? Int64("\($0)") }.min()
            var cat: Category = .all
            if let f = firstId {
                switch f {
                case 1000000...1999999: cat = .music
                case 2000000...2999999: cat = .series
                case 3000000...3999999: cat = .movies
                case 4000000...4999999: cat = .apps
                case 5000000...5999999: cat = .porn
                case 6000000...6999999: cat = .anime
                case 7000000...7999999: cat = .games
                case 9000000...9999999: cat = .books
                case 10000000...10999999: cat = .other
                default: cat = .all
                }
            }
            return Torrent(id: torrentId(o.str("id") ?? TorrentUtils.infoHash(magnet) ?? magnet), name: title,
                           size: o.double("bytes").map(FileSizeUtils.formatBytes), seeders: o.uint("seeders"),
                           peers: o.uint("peers"), providerName: name,
                           uploadDate: o.str("date").flatMap(TorrentDateParser.parseIso), category: cat,
                           detailsPageUrl: o.str("details"), magnetUri: .available(magnet))
        }
    }
}
