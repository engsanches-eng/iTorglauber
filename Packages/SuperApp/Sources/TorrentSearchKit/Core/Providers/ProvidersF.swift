import Foundation
import SwiftSoup

// Portado de: TorrentDownload, TorrentDownloads, TorrentKitty, TorrentsCSV, Torrentz.

// MARK: TorrentDownload
final class TorrentDownload: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "torrentdownloadinfo", name = "TorrentDownload", url = "https://torrentdownload.info"
    let supportedCategories: Set<Category> = [.anime, .apps, .books, .games, .movies, .music, .porn, .series, .other]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search?q=\(query)"; return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/latest"; return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/top"; return parse(try await net.getText(u), u)
    }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        guard let doc = Html.parse(html, baseUrl: pageUrl), doc.first("h3")?.own != "No Results Found" else { return [] }
        return doc.all("table.table2 > tbody > tr:has(span.smallish)").compactMap { li -> Torrent? in
            guard let a = li.first("td:nth-child(1) > div.tt-name > a"), let details = a.at("abs:href").nonBlank else { return nil }
            let hash = details.substringBeforeLast("/").takeLastWhile { $0 != "/" }.trimmed.lowercased()
            return Torrent(id: torrentId(hash), name: a.txt, size: li.first("td:nth-child(3)").ownStr,
                           seeders: li.first("td:nth-child(4)")?.own.uintLenient, peers: li.first("td:nth-child(5)")?.own.uintLenient,
                           providerName: name, uploadDate: li.first("td:nth-child(2)").ownStr.flatMap(TorrentDateParser.tryParseRelative),
                           category: li.first("td:nth-child(1) > div.tt-name > span").ownStr.map(Self.category),
                           detailsPageUrl: details, magnetUri: .available(TorrentUtils.createMagnetUri(hash)))
        }
    }
    static func category(_ rawIn: String) -> Category {
        let raw = rawIn.filter { $0.isASCII && $0.isLetter }
        switch raw {
        case "XXX", "XXXVideo", "XXXHDVideo", "XXXPictures", "Adult", "AdultPornHDVideo", "AdultPornPictures", "AdultPornVideo": return .porn
        case "Anime", "AnimeEnglishtranslated", "AnimeAnimeOther": return .anime
        case "Applications", "ApplicationsAndroid", "ApplicationsWindows", "Software": return .apps
        case "BooksAcademic", "BooksComics", "BooksEbooks", "BooksEducational", "BooksMagazines", "BooksFiction", "BooksNonfiction",
             "BooksTextbooks", "Ebooks", "OtherEbooks", "OtherComics", "AudioBooks", "AudioAudiobooks": return .books
        case "Games", "GamesWindows": return .games
        case "Movies", "MoviesAction", "MoviesConcerts", "MoviesCrime", "MoviesDocumentary", "MoviesDubbedMovies",
             "MoviesHighresMovies", "MoviesMusicvideos", "MoviesThriller", "VideoMovies": return .movies
        case "Music", "MusicHardrock", "MusicMp", "MusicFLAC", "MusicLossless", "MusicRB", "MusicTranceHouseDance", "VideoMusic", "AudioMusic": return .music
        case "TV", "TVBBC", "TVshows", "Television": return .series
        default: return .other
        }
    }
}

// MARK: TorrentDownloads
final class TorrentDownloads: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "torrentdownloads", name = "TorrentDownloads", url = "https://torrentdownloads.pro"
    var cloudflareSolverUrl: String? { "\(url)/search/?s_cat=0&search=ubuntu" }
    let supportedCategories: Set<Category> = [.anime, .apps, .books, .games, .movies, .music, .series, .other]
    let isCloudflareProtected = true
    let enabledByDefault = true

    func search(query: String, category: Category) async throws -> [Torrent] {
        let cid: Int
        switch category {
        case .all: cid = 0
        case .anime: cid = 1
        case .apps: cid = 7
        case .books: cid = 2
        case .games: cid = 3
        case .movies: cid = 4
        case .music: cid = 5
        case .series: cid = 8
        case .porn, .other: cid = 9
        }
        let u = "\(url)/search/?s_cat=\(cid)&search=\(query)"
        return parse(try await net.getText(u), u)
    }
    private func page(_ kind: String, _ c: Category, fallback: String) -> String {
        let names: [Category: String] = [.anime: "Anime", .apps: "Software", .books: "Books", .games: "Games", .movies: "Movies",
                                         .music: "Music", .series: "TV_Shows", .other: "Other"]
        return names[c].map { "\(url)/view/\(kind)/\($0).html" } ?? "\(url)/\(fallback)"
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = page("today", category, fallback: "most-active"); return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = page("popular", category, fallback: "most-seeded"); return parse(try await net.getText(u), u)
    }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url) }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        let rows = Html.parse(html, baseUrl: pageUrl)?.all("div.inner_container").last?.all("div.grey_bar3") ?? []
        return rows.dropFirst(2).compactMap { li -> Torrent? in
            guard let a = li.first("p:nth-child(1) > a:nth-child(2)"), let details = a.at("abs:href").nonBlank, !a.own.isEmpty else { return nil }
            return Torrent(id: torrentId(details), name: a.own, size: li.first("span:nth-child(5)").ownStr,
                           seeders: li.first("span:nth-child(4)")?.own.uint, peers: li.first("span:nth-child(3)")?.own.uint,
                           providerName: name,
                           category: li.first("p:nth-child(1) > img:nth-child(1)").attrStr("src").map(Self.category),
                           detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
    static func category(_ src: String) -> Category {
        switch src.removingPrefix("/templates/new/images/icons/") {
        case "menu_icon0.png": return .all
        case "menu_icon1.png": return .anime
        case "menu_icon2.png": return .books
        case "menu_icon3.png": return .games
        case "menu_icon4.png": return .movies
        case "menu_icon5.png": return .music
        case "menu_icon7.png": return .apps
        case "menu_icon8.png": return .series
        default: return .other
        }
    }
}

// MARK: TorrentKitty
final class TorrentKitty: SearchProvider {
    let id = "torrentkitty", name = "TorrentKitty", url = "https://torrentkitty.tv"
    let supportedCategories: Set<Category> = [.other]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search/\(query)"
        return (Html.parse(try await net.getText(u), baseUrl: u)?.all("table#archiveResult > tbody > tr") ?? []).dropFirst().compactMap { li -> Torrent? in
            guard let n = li.first("td.name")?.own,
                  let magnet = li.first("td.action > a:nth-child(2)")?.at("href"),
                  let hash = TorrentUtils.infoHash(magnet) else { return nil }
            return Torrent(id: torrentId(hash), name: n, size: li.first("td.size").ownStr.map { $0.uppercased() }, providerName: name,
                           uploadDate: li.first("td.date").ownStr.flatMap { TorrentDateParser.parse($0, format: "yyyy-MM-dd") },
                           detailsPageUrl: li.first("td.action > a:nth-child(1)")?.at("abs:href"), magnetUri: .available(magnet),
                           fileDownloadLink: li.first("td.action > a:nth-child(3)")?.at("abs:href"))
        }
    }
}

// MARK: TorrentsCSV
final class TorrentsCSV: SearchProvider {
    let id = "torrentscsv", name = "TorrentsCSV", url = "https://torrents-csv.com"
    let supportedCategories: Set<Category> = [.other]
    let enabledByDefault = true

    func search(query: String, category: Category) async throws -> [Torrent] {
        let json = try await net.getJson("\(url)/service/search?q=\(query)") as? JObj
        return (json?.objs("torrents") ?? []).compactMap { o -> Torrent? in
            guard let n = o.str("name"), let hash = o.str("infohash"), let rid = o.long("id") else { return nil }
            return Torrent(id: torrentId(String(rid)), name: n, size: o.double("size_bytes").map(FileSizeUtils.formatBytes),
                           seeders: o.uint("seeders"), peers: o.uint("leechers"), providerName: name,
                           uploadDate: o.long("created_unix").map(TorrentDateParser.epochSecondToDate), category: .other,
                           magnetUri: .available(TorrentUtils.createMagnetUri(hash)))
        }
    }
}

// MARK: Torrentz
final class Torrentz: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "torrentz", name = "Torrentz", url = "https://torrentz2.nz"
    let supportedCategories: Set<Category> = [.other, .movies, .series, .anime, .apps, .games, .music, .books, .porn]
    let enabledByDefault = false
    private let categoryMap: [Category: Int] = [.other: 1, .movies: 2, .series: 3, .anime: 4, .apps: 5, .games: 6, .music: 7, .books: 9, .porn: 10]

    func search(query: String, category: Category) async throws -> [Torrent] {
        var u = "\(url)/search?q=\(query)"
        if category != .all, let c = categoryMap[category] { u += "&category=\(c)" }
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        var u = "\(url)/latest"
        if category != .all, let c = categoryMap[category] { u += "?category=\(c)" }
        return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        var u = "\(url)/trending"
        if category != .all, let c = categoryMap[category] { u += "?category=\(c)" }
        return parse(try await net.getText(u), u)
    }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url, selector: #"div.download a[href^="magnet:?"]"#) }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("div.results > dl") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("dt > a"), let details = a.at("abs:href").nonBlank, !a.own.isEmpty else { return nil }
            let date = li.first("dd > span.a > span").attrStr("title").flatMap { raw -> Date? in
                if let d = TorrentDateParser.parseIso(raw) { return d }
                guard let p = raw.range(of: "(", options: .backwards) else { return nil }
                var s = String(raw[..<p.upperBound]).dropLast(2)
                while let last = s.last, !last.isWhitespace { s = s.dropLast() }
                return TorrentDateParser.parse(String(s).trimmed, format: "E MMM dd yyyy HH:mm:ss")
            }
            let rawCat = li.first("dt").ownStr.map { $0.trimmed.removingPrefix("» ") }
            return Torrent(id: torrentId(details.takeLastWhile { $0 != "/" }), name: a.own, size: li.first("dd > span.s").ownStr,
                           seeders: li.first("dd > span.u")?.own.uintLenient, peers: li.first("dd > span.d")?.own.uintLenient,
                           providerName: name, uploadDate: date, category: rawCat.map(Self.category),
                           detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
    static func category(_ raw: String) -> Category {
        if raw.hasPrefix("Anime") { return .anime }
        if raw.hasPrefix("Other") { return .other }
        if raw.hasPrefix("Softwares") { return .apps }
        if raw.hasPrefix("Music") { return .music }
        if raw.hasPrefix("Games") { return .games }
        if raw == "Movies" { return .movies }
        if raw == "TV" { return .series }
        return .other
    }
}
