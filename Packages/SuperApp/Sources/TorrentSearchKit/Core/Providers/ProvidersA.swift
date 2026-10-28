import Foundation
import SwiftSoup

// Portado de: AniLibria, AniRena, AnimeTosho, AudioBookBay, BTDigg, BangumiMoe,
// BitSearch, BlueRoms, Bt4g, Btsow, Dmhy, EpubLibre (TorrentSearch v0.5.2).

// MARK: AniLibria
final class AniLibria: SearchProvider {
    let id = "anilibria", name = "AniLibria", url = "https://www.anilibria.top"
    let supportedCategories: Set<Category> = [.anime]
    let enabledByDefault = false
    private let api = "https://anilibria.top/api/v1"

    func search(query: String, category: Category) async throws -> [Torrent] {
        let json = try await net.getJson("\(api)/app/search/releases?query=\(query)")
        let ids = Array(jsonObjects(json).compactMap { $0.long("id") }.prefix(15))
        return try await concurrentMap(ids) { try await self.fetchRelease($0) }.flatMap { $0 }
    }

    private func fetchRelease(_ releaseId: Int64) async throws -> [Torrent] {
        let json = try await net.getJson("\(api)/anime/torrents/release/\(releaseId)")
        return jsonObjects(json).compactMap(parse)
    }

    private func parse(_ o: JObj) -> Torrent? {
        guard let hash = o.str("hash") else { return nil }
        let release = o.obj("release")
        guard let name = o.str("label") ?? release?.obj("name").flatMap({ $0.str("english") ?? $0.str("main") }) else { return nil }
        return Torrent(
            id: torrentId(o.long("id").map(String.init) ?? hash), name: name,
            size: o.double("size").map(FileSizeUtils.formatBytes),
            seeders: o.uint("seeders"), peers: o.uint("leechers"), providerName: self.name,
            uploadDate: o.str("created_at").flatMap(TorrentDateParser.parseIso), category: .anime,
            detailsPageUrl: release?.str("alias").map { "\(url)/anime/releases/release/\($0)" },
            magnetUri: .available(o.str("magnet") ?? TorrentUtils.createMagnetUri(hash)))
    }
}

// MARK: AniRena
final class AniRena: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "anirena", name = "AniRena", url = "https://anirena.com"
    let supportedCategories: Set<Category> = [.anime, .apps, .books, .music, .porn, .series, .other]
    let enabledByDefault = false
    private let categoryMap: [Category: String] = [
        .anime: "anime", .apps: "software", .books: "manga", .music: "audio",
        .porn: "hentai", .series: "live", .other: "other",
    ]

    func search(query: String, category: Category) async throws -> [Torrent] {
        var u = "\(url)?q=\(query)&page=1"
        if category != .all, let c = categoryMap[category] { u += "&cat=\(c)" }
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] { parse(try await net.getText(url), url) }
    func getTopTorrents(category: Category) async throws -> [Torrent] { try await getLatestTorrents(category: category) }
    func getMagnetUri(url: String) async throws -> String {
        guard let m = try await net.getLocation(url) else { throw ProviderParseError(message: "Magnet não encontrado") }
        return m
    }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        let name = "td.col-name > div.tl-name-wrap > a.tl-torrent-name"
        return (Html.parse(html, baseUrl: pageUrl)?.all("table.tl-table > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let tname = li.first(name)?.own,
                  let src = li.first("td.col-actions > div.tl-actions > a:nth-child(1)")?.at("abs:href") else { return nil }
            let remoteId = li.first(name)?.at("data-torrent-id").nonBlank ?? src.removingSurrounding("/torrrents/", "/magnet")
            let cat = li.first("td.col-cat")?.at("title").nonBlank?.takeWhile { $0 != "/" }.trimmed
            return Torrent(
                id: torrentId(remoteId), name: tname, size: li.first("td.col-size")?.own,
                seeders: li.first("td.col-se > span.tl-se")?.own.uint, peers: li.first("td.col-le > span.tl-le")?.own.uint,
                providerName: self.name,
                uploadDate: li.at("data-created-ts").nonBlank.flatMap { Int64($0) }.map(TorrentDateParser.epochSecondToDate),
                category: cat.map(Self.category), detailsPageUrl: li.first(name)?.at("abs:href"),
                magnetUri: .requiresFetch(src),
                fileDownloadLink: li.first("td.col-actions > div.tl-actions > a:nth-child(2)")?.at("abs:href"))
        }
    }

    static func category(_ raw: String) -> Category {
        switch raw {
        case "Anime": return .anime
        case "Manga", "Literature": return .books
        case "Audio": return .music
        case "Live Action": return .series
        case "Software": return .apps
        case "Hentai": return .porn
        default: return .other
        }
    }
}

// MARK: AnimeTosho
final class AnimeTosho: SearchProvider {
    let id = "animetosho", name = "AnimeTosho", url = "https://animetosho.org"
    let supportedCategories: Set<Category> = [.anime]
    let enabledByDefault = true

    func search(query: String, category: Category) async throws -> [Torrent] {
        let html = try await net.getText("\(url)/search?q=\(query)")
        return (Html.parse(html)?.all("div.home_list_entry") ?? []).compactMap { e -> Torrent? in
            guard let a = e.first("div.link > a"), let details = a.at("href").nonBlank,
                  let links = e.first("div.links"),
                  let magnet = links.first(#"a[href^="magnet:"]"#)?.at("href") else { return nil }
            var seeds = 0, peers = 0
            if let span = links.all("span").first(where: { $0.has("title") }),
               let g = span.own.allGroups(#"\[(\d+)↑/(\d+)↓]"#) {
                seeds = g[1].uint ?? 0; peers = g[2].uint ?? 0
            }
            var date: Date?
            if let raw = e.first("div.date")?.at("title").removingPrefix("Date/time submitted: ").trimmed {
                if raw.hasPrefix("Today") { date = TorrentDateParser.getTodayDate() }
                else if raw.hasPrefix("Yesterday") { date = TorrentDateParser.getYesterdayDate() }
                else if let d = raw.split(separator: " ", maxSplits: 1).first {
                    date = TorrentDateParser.parse(String(d), format: "d/M/yyyy")
                }
            }
            return Torrent(id: torrentId(details), name: a.txt, size: e.first("div.size")?.own,
                           seeders: seeds, peers: peers, providerName: name, uploadDate: date, category: .anime,
                           detailsPageUrl: details, magnetUri: .available(magnet),
                           fileDownloadLink: links.first("a.dllink")?.at("href"))
        }
    }
}

// MARK: AudioBookBay
final class AudioBookBay: SearchProvider, LatestTorrentsProvider, MagnetUriProvider {
    let id = "audiobookbay", name = "AudioBookBay", url = "https://audiobookbay.lu"
    let supportedCategories: Set<Category> = [.books]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/?s=\(query)"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] { parse(try await net.getText(url), url) }
    func getMagnetUri(url: String) async throws -> String {
        let doc = Html.parse(try await net.getText(url))
        guard let hash = doc?.first("td:containsOwn(Info Hash:)")?.nextEl?.own.nonBlank else {
            throw ProviderParseError(message: "Info hash não encontrado")
        }
        return TorrentUtils.createMagnetUri(hash)
    }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("div.post") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("div.postTitle > h2 > a") else { return nil }
            let tname = a.own
            let details = a.at("abs:href")
            guard !tname.isEmpty, !details.isEmpty else { return nil }
            let info = li.first("div.postContent > p:nth-child(3)")?.wholeText.lines
            let size = info?.first { $0.hasPrefix("File Size: ") }?.substringAfter("File Size: ").trimmed.removingSuffix("s")
            let rawDate = info?.first { $0.hasPrefix("Posted: ") }?.substringAfter("Posted: ").trimmed
            let date = rawDate.flatMap { TorrentDateParser.parse($0, format: "d MMM yyyy") }
            return Torrent(id: torrentId(details), name: tname, size: size, providerName: name, uploadDate: date,
                           category: .books, detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
}

// MARK: BTDigg
final class BTDigg: SearchProvider {
    let id = "btdigg", name = "BTDigg", url = "https://btdig.com"
    let supportedCategories: Set<Category> = [.other]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "https://btdig.com/search?q=\(query)"
        return (Html.parse(try await net.getText(u), baseUrl: u)?.all("div.one_result > div") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("div.torrent_name > a"),
                  let magnet = li.first("div.torrent_magnet > div.fa-magnet > a")?.at("href"),
                  let hash = TorrentUtils.infoHash(magnet) else { return nil }
            return Torrent(id: torrentId(hash), name: a.txt, size: li.first("span.torrent_size")?.own, providerName: name,
                           uploadDate: li.first("span.torrent_age").ownStr.map { $0.removingPrefix("found ") }.flatMap(TorrentDateParser.tryParseRelative),
                           detailsPageUrl: a.at("abs:href"), magnetUri: .available(magnet))
        }
    }
}

// MARK: BangumiMoe
final class BangumiMoe: SearchProvider, LatestTorrentsProvider {
    let id = "bangumimoe", name = "BangumiMoe", url = "https://bangumi.moe"
    let supportedCategories: Set<Category> = [.anime]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        // O original envia o texto já codificado; mantemos o comportamento.
        parse(try await net.postJson("\(url)/api/v2/torrent/search", payload: ["query": query.uriDecoded]))
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        parse(try await net.getJson("\(url)/api/torrent/latest"))
    }
    private func parse(_ json: Any?) -> [Torrent] {
        ((json as? JObj)?.objs("torrents") ?? []).compactMap { o -> Torrent? in
            guard let title = o.str("title"), let magnet = o.str("magnet") else { return nil }
            let rid = o.str("_id")
            return Torrent(id: torrentId(rid ?? TorrentUtils.infoHash(magnet) ?? magnet), name: title, size: o.str("size"),
                           seeders: o.uint("seeders"), peers: o.uint("leechers"), providerName: name,
                           uploadDate: o.str("publish_time").flatMap(TorrentDateParser.parseIso), category: .anime,
                           detailsPageUrl: rid.map { "\(url)/torrent/\($0)" }, magnetUri: .available(magnet))
        }
    }
}

// MARK: BitSearch
final class BitSearch: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "bitsearch", name = "BitSearch", url = "https://bitsearch.to"
    let supportedCategories: Set<Category> = [.anime, .apps, .books, .games, .movies, .music, .porn, .series, .other]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let cid = categoryId(category)
        return try await concurrentMap(Array(1...5)) { page in
            var u = "\(self.url)/search?q=\(query)&page=\(page)&sortBy=seeders"
            if let cid { u += "&category=\(cid)" }
            return self.parse(try await self.net.getText(u), u)
        }.flatMap { $0 }
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        var u = "\(url)/latest"; if let c = categoryId(category) { u += "?category=\(c)" }
        return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        var u = "\(url)/trending"; if let c = categoryId(category) { u += "?category=\(c)" }
        return parse(try await net.getText(u), u)
    }
    private func categoryId(_ c: Category) -> Int? {
        switch c {
        case .all: return nil
        case .anime: return 4
        case .apps: return 5
        case .books: return 9
        case .games: return 6
        case .movies: return 2
        case .music: return 7
        case .porn: return 10
        case .series: return 3
        case .other: return 1
        }
    }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        let info = "> div:nth-child(1)", dl = "> div:nth-child(2)"
        let meta = "\(info) > div:nth-last-child(2)", swarm = "\(info) > div:nth-last-child(1)"
        return (Html.parse(html, baseUrl: pageUrl)?.all("div.space-y-4 > div > div:nth-child(1)") ?? []).compactMap { li -> Torrent? in
            guard let nameEl = li.first("\(info) h3"),
                  let magnet = li.first("\(dl) > a:nth-child(2)")?.at("href"), !magnet.isEmpty else { return nil }
            let rid = nameEl.at("href").takeLastWhile { $0 != "/" }.nonBlank ?? TorrentUtils.infoHash(magnet) ?? magnet
            let date = li.first("\(meta) > span:nth-child(3) > span").ownStr.flatMap {
                TorrentDateParser.parse($0, format: "M/d/yyyy") ?? TorrentDateParser.tryParseRelative($0)
            }
            return Torrent(id: torrentId(rid), name: nameEl.txt, size: li.first("\(meta) > span:nth-child(2) > span")?.own,
                           seeders: li.first("\(swarm) > span:nth-child(1) > span:nth-child(2)")?.own.uint,
                           peers: li.first("\(swarm) > span:nth-child(2) > span:nth-child(2)")?.own.uint,
                           providerName: name, uploadDate: date,
                           category: li.first("\(meta) > span:nth-child(1) > span").ownStr.map(Self.category),
                           detailsPageUrl: li.first("\(info) h3 > a")?.at("abs:href"),
                           magnetUri: .available(magnet), fileDownloadLink: li.first("\(dl) > a:nth-child(1)")?.at("abs:href"))
        }
    }
    static func category(_ raw: String) -> Category {
        if raw.hasPrefix("Movies") { return .movies }
        if raw == "TV" { return .series }
        if raw.hasPrefix("Anime") { return .anime }
        if raw.hasPrefix("Softwares") { return .apps }
        if raw.hasPrefix("Games") { return .games }
        if raw.hasPrefix("Music") { return .music }
        if raw == "AudioBook" || raw == "Ebook/Course" { return .books }
        if raw == "XXX" { return .porn }
        return .other
    }
}

// MARK: BlueRoms
final class BlueRoms: SearchProvider, MagnetUriProvider {
    let id = "blueroms", name = "BlueRoms", url = "https://www.blueroms.ws"
    let supportedCategories: Set<Category> = [.games]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search?g=0&p=0&q=\(query)"
        return (Html.parse(try await net.getText(u), baseUrl: u)?.all("div.row > div.col-xs-12 > div.card") ?? []).compactMap { li -> Torrent? in
            guard let dl = li.first("div.card-footer > a")?.at("abs:href").nonBlank,
                  let game = li.first("h4.card-title > a")?.own.nonBlank else { return nil }
            let platform = li.first("strong:containsOwn(Platform:)")?.nextEl?.own
            let size = (li.first("strong:containsOwn(Size:)")?.nextSibling() as? TextNode)?.getWholeText().trimmed
            return Torrent(id: torrentId(dl.takeLastWhile { $0 != "/" }), name: platform.map { "\(game) - \($0)" } ?? game,
                           size: size.map(FileSizeUtils.normalizeSize), providerName: name, category: .games,
                           detailsPageUrl: li.first("h4.card-title > a")?.at("abs:href"), magnetUri: .requiresFetch(dl))
        }
    }
    func getMagnetUri(url: String) async throws -> String {
        let doc = Html.parse(try await net.getText(url))
        guard let enc = doc?.first("button#magnet-button")?.at("data-link").nonBlank,
              let data = Data(base64Encoded: enc), let m = String(data: data, encoding: .utf8) else {
            throw ProviderParseError(message: "Magnet não encontrado")
        }
        return m
    }
}

// MARK: BT4G
final class Bt4g: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "bt4g", name = "BT4G", url = "https://bt4gprx.com"
    var cloudflareSolverUrl: String? { "\(url)/search?q=ubuntu" }
    let supportedCategories: Set<Category> = [.apps, .books, .movies, .music, .other]
    let isCloudflareProtected = true
    let enabledByDefault = false
    private let categoryMap: [Category: String] = [.all: "all", .apps: "app", .books: "doc", .movies: "movie", .music: "audio", .other: "other"]

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search?q=\(query)&category=\(categoryMap[category] ?? "all")&orderby=seeders&p=1"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] { parse(try await net.getText("\(url)/new"), "\(url)/new") }
    func getTopTorrents(category: Category) async throws -> [Torrent] { parse(try await net.getText("\(url)/week"), "\(url)/week") }
    func getMagnetUri(url: String) async throws -> String {
        let doc = Html.parse(try await net.getText(url))
        guard let hash = doc?.first(#"a[href^="//downloadtorrentfile.com/hash/"]"#)?.at("href")
            .removingPrefix("//downloadtorrentfile.com/hash/").takeWhile({ $0 != "?" }).nonBlank else {
            throw ProviderParseError(message: "Info hash não encontrado")
        }
        return TorrentUtils.createMagnetUri(hash)
    }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("div.notion-list-item") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("div.notion-list-item-title > a"), let details = a.at("abs:href").nonBlank else { return nil }
            let raw = li.first("div.notion-list-item-meta > span:nth-child(2)")?.own.removingPrefix("Creation Time: ").trimmed
            return Torrent(id: torrentId(details.takeLastWhile { $0 != "/" }), name: a.txt,
                           size: li.first("div.notion-list-item-meta > span:nth-child(5) > b").ownStr.map(FileSizeUtils.normalizeSize),
                           seeders: li.first("div.notion-list-item-meta span#seeders")?.own.uint,
                           peers: li.first("div.notion-list-item-meta span#leechers")?.own.uint, providerName: name,
                           uploadDate: raw.flatMap { TorrentDateParser.parse($0, format: "yyyy-MM-dd") ?? TorrentDateParser.tryParseRelative($0) },
                           category: li.first("div.notion-list-item-meta span.notion-tag").ownStr.map(Self.category),
                           detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
    static func category(_ raw: String) -> Category {
        switch raw {
        case "Video", "Movie": return .movies
        case "Audio": return .music
        case "Doc": return .books
        case "App", "Application": return .apps
        default: return .other
        }
    }
}

// MARK: Btsow
final class Btsow: SearchProvider {
    let id = "btsow", name = "Btsow", url = "https://btsow.live"
    let supportedCategories: Set<Category> = [.other]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let payload: [Any] = [["search": query.uriDecoded], 30, 1]
        let json = try await net.postJson("https://btsow.live/bts/data/api/search", payload: payload)
        return ((json as? JObj)?.objs("data") ?? []).compactMap { o -> Torrent? in
            guard let n = o.str("name")?.replacingOccurrences(of: "<em>", with: "").replacingOccurrences(of: "</em>", with: ""),
                  let hash = o.str("hash")?.lowercased() else { return nil }
            return Torrent(id: torrentId(hash), name: n, size: o.double("size").map(FileSizeUtils.formatBytes),
                           providerName: name, detailsPageUrl: "\(url)/magnet/detail/\(hash)",
                           magnetUri: .available(TorrentUtils.createMagnetUri(hash)))
        }
    }
}

// MARK: Dmhy
final class Dmhy: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "dmhy", name = "Dmhy", url = "https://share.dmhy.org"
    let supportedCategories: Set<Category> = [.anime, .books, .games, .music, .series, .other]
    let enabledByDefault = false
    private let categoryMap: [Category: Int] = [.all: 0, .anime: 2, .books: 3, .games: 9, .music: 4, .series: 6, .other: 1]

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/topics/list?keyword=\(query)&sort_id=\(categoryMap[category] ?? 0)&team_id=0&order=date-desc"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/topics/list/sort_id/\(categoryMap[category] ?? 0)"
        return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] { try await getLatestTorrents(category: category) }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("table#topic_list > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("td.title > a"),
                  let magnet = li.first(#"td:nth-child(4) > a[href^="magnet:?xt="]"#)?.at("href"),
                  let hash = TorrentUtils.infoHash(magnet) else { return nil }
            let catId = (try? li.first("td:nth-child(2) > a")?.className())?.removingPrefix("sort-")
            return Torrent(id: torrentId(hash), name: a.own, size: li.first("td:nth-child(5)").ownStr.map(FileSizeUtils.normalizeSize),
                           seeders: li.first("td:nth-child(6)")?.txt.uint, peers: li.first("td:nth-child(7)")?.txt.uint,
                           providerName: name,
                           uploadDate: li.first("td:nth-child(1) > span").ownStr.flatMap { TorrentDateParser.parse($0, format: "yyyy/MM/dd HH:mm") },
                           category: catId.map(Self.category), detailsPageUrl: a.at("abs:href"), magnetUri: .available(magnet))
        }
    }
    static func category(_ id: String) -> Category {
        switch id {
        case "2", "7", "31": return .anime
        case "3": return .books
        case "41", "42", "6": return .series
        case "4", "43", "44", "15": return .music
        case "9", "17", "18", "19", "20", "21": return .games
        default: return .other
        }
    }
}

// MARK: EpubLibre
final class EpubLibre: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "epublibre", name = "EpubLibre", url = "https://epublibre.org"
    let supportedCategories: Set<Category> = [.books]
    let enabledByDefault = false
    private let ajax = ["X-Requested-With": "XMLHttpRequest"]

    func search(query: String, category: Category) async throws -> [Torrent] {
        parse(try await net.postJson("\(url)/catalogo/index/0/nuevo/todos/sin/todos/\(query)/ajax", headers: ajax))
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        parse(try await net.postJson("\(url)/catalogo/index/0/nuevo/novedades/sin/todos/--/ajax", headers: ajax))
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        parse(try await net.postJson("\(url)/catalogo/index/0/valorado/novedades/sin/todos/--/ajax", headers: ajax))
    }
    func getMagnetUri(url: String) async throws -> String {
        guard let m = Html.parse(try await net.getText(url))?.first("a#en_desc")?.at("href").nonBlank else {
            throw ProviderParseError(message: "Magnet não encontrado")
        }
        return m
    }
    private func parse(_ json: Any?) -> [Torrent] {
        guard let html = (json as? JObj)?.str("contenido") else { return [] }
        return (Html.parse(html)?.all("div.span2") ?? []).compactMap { li -> Torrent? in
            guard let book = li.first("a#stk > div.texto-portada > h1")?.own,
                  let details = li.first("a#stk")?.at("href").nonBlank else { return nil }
            var n = book
            if let author = li.first("a#stk > div.texto-portada > h2")?.own { n += " - \(author)" }
            return Torrent(id: torrentId(details.takeLastWhile { $0 != "/" }.nonBlank ?? details), name: n, providerName: name,
                           category: .books, detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
}
