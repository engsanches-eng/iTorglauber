import Foundation
import SwiftSoup

// Portado de: ThePirateBay, TheRarBg, 1337x, TokyoToshokan, Torrent9, TorrentDatabase.

// MARK: ThePirateBay (API apibay.org)
final class ThePirateBay: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "thepiratebay", name = "ThePirateBay", url = "https://thepiratebay.org"
    let supportedCategories: Set<Category> = [.apps, .books, .games, .movies, .music, .porn, .series, .other]
    let safety: ProviderSafety = .unsafe(reason: L("Muitos relatos de malware por falta de moderação."))
    let enabledByDefault = false
    private let api = "https://apibay.org"

    func search(query: String, category: Category) async throws -> [Torrent] {
        parse(try await net.getJson("\(api)/q.php?q=\(query)&cat=\(cid(category))"))
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = category == .all ? "\(api)/precompiled/data_top100_recent.json" : "\(api)/q.php?q=category%3A\(cid(category))"
        return parse(try await net.getJson(u))
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = category == .all ? "\(api)/precompiled/data_top100_48h.json" : "\(api)/precompiled/data_top100_48h_\(cid(category)).json"
        return parse(try await net.getJson(u))
    }
    private func cid(_ c: Category) -> Int {
        switch c {
        case .all, .anime: return 0
        case .apps: return 300
        case .books: return 601
        case .games: return 400
        case .movies, .series: return 200
        case .music: return 101
        case .porn: return 500
        case .other: return 600
        }
    }
    private func parse(_ json: Any?) -> [Torrent] {
        jsonObjects(json).compactMap { o -> Torrent? in
            guard let n = o.str("name"), n != "No results returned",
                  let hash = o.str("info_hash")?.lowercased().trimmed, let rid = o.str("id") else { return nil }
            return Torrent(id: torrentId(rid), name: n, size: o.str("size").flatMap { FileSizeUtils.formatBytes($0) },
                           seeders: o.str("seeders")?.uint, peers: o.str("leechers")?.uint, providerName: name,
                           uploadDate: o.str("added").flatMap { Int64($0) }.map(TorrentDateParser.epochSecondToDate),
                           category: o.str("category").flatMap { Int($0) }.map(Self.category),
                           detailsPageUrl: "\(url)/description.php?id=\(rid)", magnetUri: .available(TorrentUtils.createMagnetUri(hash)))
        }
    }
    static func category(_ id: Int) -> Category {
        switch id {
        case 300...306, 399: return .apps
        case 601: return .books
        case 400...408, 499: return .games
        case 201, 202, 204, 207, 209, 210, 211: return .movies
        case 100...104, 199: return .music
        case 500...507, 599: return .porn
        case 205, 208, 212: return .series
        default: return .other
        }
    }
}

// MARK: TheRarBg
final class TheRarBg: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "therarbag", name = "TheRarBg", url = "https://therarbg.com"
    let supportedCategories: Set<Category> = [.anime, .apps, .books, .games, .movies, .music, .porn, .series, .other]
    let safety: ProviderSafety = .unsafe(reason: L("Clone do RARBG original com muitos torrents falsos. Use com extremo cuidado."))
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        var u = "\(url)/get-posts/keywords:\(query)"
        if category != .all { u += ":category:\(cname(category))" }
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        var u = "\(url)/get-posts/time:2D"
        if category != .all { u += ":category:\(cname(category))" }
        return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        var u = "\(url)/get-posts/time:2D:order:-se"
        if category != .all { u += ":category:\(cname(category))" }
        return parse(try await net.getText(u), u)
    }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url) }

    private func cname(_ c: Category) -> String {
        switch c {
        case .all: return ""
        case .anime: return "Anime"
        case .apps: return "Apps"
        case .books: return "Books"
        case .games: return "Games"
        case .movies: return "Movies"
        case .music: return "Music"
        case .porn: return "XXX"
        case .series: return "Tv"
        case .other: return "Other"
        }
    }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("table > tbody > tr.list-entry") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("td.cellName > div > a"), let details = a.at("abs:href").nonBlank, !a.own.isEmpty else { return nil }
            return Torrent(id: torrentId(details), name: a.own,
                           size: li.first("td.sizeCell").attrStr("data-order").flatMap { FileSizeUtils.formatBytes($0) },
                           seeders: li.first("td:nth-child(7)")?.own.uint, peers: li.first("td:nth-child(8)")?.own.uint,
                           providerName: name,
                           uploadDate: li.first("td:nth-child(4)").attrStr("data-order").flatMap { Int64($0) }.map(TorrentDateParser.epochSecondToDate),
                           category: li.first("td:nth-child(3) > a").ownStr.map(Self.category),
                           detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
    static func category(_ raw: String) -> Category {
        switch raw {
        case "Anime": return .anime
        case "Apps": return .apps
        case "Books": return .books
        case "Games": return .games
        case "Movies": return .movies
        case "Music": return .music
        case "XXX": return .porn
        case "Tv": return .series
        default: return .other
        }
    }
}

// MARK: 1337x
final class ThirteenThirtySevenX: SearchProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "1337x", name = "1337x", url = "https://1337x.to"
    let supportedCategories: Set<Category> = [.anime, .apps, .games, .movies, .music, .other, .porn, .series]
    let isCloudflareProtected = true
    let enabledByDefault = false
    private let categoryMap: [Category: String] = [.anime: "Anime", .apps: "Apps", .games: "Games", .movies: "Movies", .music: "Music", .other: "Other", .porn: "XXX", .series: "TV"]

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = category == .all ? "\(url)/search/\(query)/1/" : "\(url)/category-search/\(query)/\(categoryMap[category] ?? "Other")/1/"
        return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/top-100"; return parse(try await net.getText(u), u)
    }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url) }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("table.table-list > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("td.name > a:nth-child(2)"), let details = a.at("abs:href").nonBlank, !a.own.isEmpty else { return nil }
            let catId = li.first("td.name > a:nth-child(1)").attrStr("href").map { $0.removingPrefix("/sub/").takeWhile { $0 != "/" } }
            return Torrent(id: torrentId(details), name: a.own,
                           size: li.first("td.size").ownStr.map { $0.replacingOccurrences(of: ",", with: "") },
                           seeders: li.first("td.seeds")?.own.uint, peers: li.first("td.leeches")?.own.uint, providerName: name,
                           uploadDate: li.first("td.coll-date").ownStr.flatMap(Self.parseDate),
                           category: catId.map(Self.category), detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
    static func parseDate(_ date: String) -> Date? {
        var d = date
        if let re = try? NSRegularExpression(pattern: #"(\d+)(st|nd|rd|th)"#) {
            d = re.stringByReplacingMatches(in: d, range: NSRange(d.startIndex..., in: d), withTemplate: "$1")
        }
        if let re = try? NSRegularExpression(pattern: #"(?<=\d)(am|pm)\b"#) {
            d = re.stringByReplacingMatches(in: d, range: NSRange(d.startIndex..., in: d), withTemplate: " $1")
        }
        d = d.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "'", with: "")
        return TorrentDateParser.parse(d, format: "MMM d yy")
            ?? TorrentDateParser.parse("\(d) \(TorrentDateParser.getCurrentYear())", format: "h a MMM d yyyy")
            ?? TorrentDateParser.tryParseTime(d)
    }
    static func category(_ id: String) -> Category {
        switch id {
        case "28", "78", "79", "80", "81": return .anime
        case "22", "23", "24", "25", "26", "27", "53", "58", "59", "60", "68", "69": return .music
        case "1", "2", "3", "4", "42", "54", "55", "66", "70", "73", "76": return .movies
        case "5", "6", "7", "41", "71", "74", "75", "9": return .series
        case "18", "19", "20", "21", "56", "57": return .apps
        case "10", "11", "12", "13", "14", "15", "16", "17", "43", "44", "45", "46", "72", "77", "82": return .games
        case "48", "49", "50", "51", "67": return .porn
        default: return .other
        }
    }
}

// MARK: TokyoToshokan
final class TokyoToshokan: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "tokyotoshokan", name = "TokyoToshokan", url = "https://tokyotosho.info"
    var cloudflareSolverUrl: String? { "\(url)/search.php?terms=one" }
    let supportedCategories: Set<Category> = [.anime, .books, .music, .porn, .other]
    let isCloudflareProtected = true
    let enabledByDefault = true
    private let categoryMap: [Category: Int] = [.all: 0, .anime: 1, .books: 3, .music: 2, .porn: 15, .other: 5]

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search.php?terms=\(query)&type=\(categoryMap[category] ?? 0)&searchName=true"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        var u = "\(url)/index.php"
        if category != .all, let c = categoryMap[category] { u += "?cat=\(c)" }
        return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] { try await getLatestTorrents(category: category) }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        let rows = Html.parse(html, baseUrl: pageUrl)?.all("table.listing > tbody > tr:nth-child(n+2)") ?? []
        return zip(rows, rows.dropFirst()).compactMap { tr1, tr2 -> Torrent? in
            guard let nameEl = tr1.first("td.desc-top > a:nth-child(2)"), !nameEl.own.isEmpty,
                  let magnet = tr1.first("td.desc-top > a:nth-child(1)")?.at("href"),
                  let hash = TorrentUtils.infoHash(magnet) else { return nil }
            let parts = tr2.first("td.desc-bot").ownStr?.split(separator: "|").dropFirst()
                .map { String($0).trimmed.drop(while: { !$0.isWhitespace }).description.trimmed }
            return Torrent(id: torrentId(hash), name: nameEl.own, size: parts?[safe: 0].map(FileSizeUtils.normalizeSize),
                           seeders: tr2.first("td.stats > span:nth-child(1)")?.own.uint,
                           peers: tr2.first("td.stats > span:nth-child(2)")?.own.uint, providerName: name,
                           uploadDate: parts?[safe: 1].flatMap { TorrentDateParser.parse($0, format: "yyyy-MM-dd HH:mm z") },
                           category: tr1.first("td:nth-child(1) > a").attrStr("href").map { Self.category($0.removingPrefix("/?cat=")) },
                           detailsPageUrl: tr1.first("td.web > a:last-child")?.at("abs:href"), magnetUri: .available(magnet),
                           fileDownloadLink: nameEl.at("abs:href"))
        }
    }
    static func category(_ id: String) -> Category {
        switch id {
        case "1", "7", "8", "10", "11": return .anime
        case "3": return .books
        case "2", "9": return .music
        case "4", "12", "13", "14", "15": return .porn
        default: return .other
        }
    }
}

// MARK: Torrent9
final class Torrent9: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "torrent9", name = "Torrent9", url = "https://www6.torrent9.to"
    let supportedCategories: Set<Category> = [.apps, .books, .games, .movies, .music, .series]
    let enabledByDefault = false
    private let categoryMap: [Category: String] = [.apps: "logiciels", .books: "ebook", .games: "jeux-pc", .movies: "films", .music: "musique", .series: "series"]

    func search(query: String, category: Category) async throws -> [Torrent] {
        var u = "\(url)/search_torrent"
        if let c = categoryMap[category] { u += "/\(c)" }
        u += "/\(query).html"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        guard let slug = categoryMap[category] else { return [] }
        let u = "\(url)/torrents_\(slug).html"; return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/top_torrent.html"; return parse(try await net.getText(u), u)
    }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url) }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("table > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("td:nth-child(1) > a"), let details = a.at("abs:href").nonBlank else { return nil }
            let icon = ((try? li.first("td:nth-child(1) > i")?.classNames()) ?? nil)?.filter { $0 != "fa" }.joined(separator: " ")
            return Torrent(id: torrentId(details), name: a.txt,
                           size: li.first("td:nth-child(3)").ownStr.map { FileSizeUtils.normalizeSize($0.replacingOccurrences(of: "o", with: "B")) },
                           seeders: li.first("td:nth-child(4) > span.seed_ok")?.own.uint, peers: li.first("td:nth-child(5)")?.own.uint,
                           providerName: name,
                           uploadDate: li.first("td:nth-child(2)").ownStr.flatMap { TorrentDateParser.parse($0, format: "dd/MM/yyyy") },
                           category: icon.map(Self.category), magnetUri: .requiresFetch(details))
        }
    }
    static func category(_ icon: String) -> Category {
        switch icon {
        case "fa-desktop": return .series
        case "fa-video-camera": return .movies
        case "fa-music": return .music
        case "fa-book": return .books
        case "fa-laptop": return .apps
        case "fa-gamepad": return .games
        default: return .other
        }
    }
}

// MARK: TorrentDatabase
final class TorrentDatabase: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "torrentdatabase", name = "TorrentDatabase", url = "https://developify.ca"
    var cloudflareSolverUrl: String? { "\(url)/search?q=ubuntu" }
    let supportedCategories: Set<Category> = [.apps, .books, .games, .movies, .music, .porn, .series]
    let isCloudflareProtected = true
    let enabledByDefault = false
    private let categoryMap: [Category: String] = [.apps: "software", .books: "e-books", .games: "games", .movies: "movies", .music: "music", .porn: "porn", .series: "tv"]

    func search(query: String, category: Category) async throws -> [Torrent] {
        var u = "\(url)/search?q=\(query)"
        if let c = categoryMap[category] { u += "&category=\(c)" }
        return parse(try await net.getText(u), u)
    }
    private func slug(_ c: Category) -> String? {
        categoryMap[c].map { c == .books ? $0.replacingOccurrences(of: "-", with: "") : $0 }
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        var u = "\(url)/newest"
        if category != .all, let s = slug(category) { u += "_\(s)" }
        return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        if category == .all { return try await getLatestTorrents(category: .all) }
        guard let s = slug(category) else { return [] }
        let u = "\(url)/top_seeded_\(s)"; return parse(try await net.getText(u), u)
    }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("table.torrent-table > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("td:nth-child(1) > a:nth-child(2)") else { return nil }
            let hash = a.at("href").removingPrefix("/track/magnet/").takeWhile { $0 != "?" }
            guard !hash.isEmpty else { return nil }
            let details = li.first("td:nth-child(1) > a:nth-child(1)")?.at("abs:href").nonBlank
            return Torrent(id: torrentId(details?.takeLastWhile { $0 != "/" } ?? hash), name: a.own,
                           size: li.first("td.size-cell").ownStr,
                           seeders: li.first("td:nth-child(5) > div > span:nth-child(1)")?.own.uint,
                           peers: li.first("td:nth-child(5) > div > span:nth-child(3)")?.own.uint, providerName: name,
                           uploadDate: li.first("td.date-cell").ownStr.flatMap { TorrentDateParser.parse($0, format: "yyyy-MM-dd HH:mm:ss") },
                           category: li.first("td:nth-child(2) > span.category-bubble").ownStr.map(Self.category),
                           detailsPageUrl: details,
                           magnetUri: .available(TorrentUtils.createMagnetUri(hash) + "&tr=https%3A%2F%2Fdevelopify.ca%2Fannounce"))
        }
    }
    static func category(_ raw: String) -> Category {
        let r = raw.lowercased()
        switch r {
        case "software": return .apps
        case "e-books", "ebooks", "audiobooks": return .books
        case "games": return .games
        case "movies": return .movies
        case "music": return .music
        case "porn", "xxx": return .porn
        case "tv": return .series
        default:
            if raw.hasPrefix("games") { return .games }
            if raw.hasPrefix("movies") { return .movies }
            if raw.hasPrefix("music") { return .music }
            if raw.hasPrefix("software") { return .apps }
            if raw.hasPrefix("tv") { return .series }
            return .other
        }
    }
}
