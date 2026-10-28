import Foundation
import SwiftSoup

// Portado de: UIndex, XXXClub, XXXTracker, Yts, ZeroMagnet.

// MARK: UIndex
final class UIndex: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "uindex", name = "UIndex", url = "https://uindex.org"
    var cloudflareSolverUrl: String? { "\(url)/search.php?search=ubuntu" }
    let supportedCategories: Set<Category> = [.anime, .apps, .games, .movies, .music, .porn, .series, .other]
    let isCloudflareProtected = true
    let enabledByDefault = true
    private let categoryMap: [Category: Int] = [.all: 0, .books: 0, .anime: 7, .apps: 5, .games: 3, .movies: 1, .music: 4, .porn: 6, .series: 2, .other: 8]

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search.php?search=\(query)&c=\(categoryMap[category] ?? 0)"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/search.php?c=\(categoryMap[category] ?? 0)"; return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/top.php?t=24h&c=\(categoryMap[category] ?? 0)"; return parse(try await net.getText(u), u)
    }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.first("table.sr-table, table.top-table")?.all("tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("td.sr-col-name > a.sr-torrent-link"),
                  let magnet = li.first("td.sr-col-name > a.sr-magnet")?.at("href"), !magnet.isEmpty else { return nil }
            let details = a.at("abs:href").nonBlank
            return Torrent(id: torrentId(details?.takeLastWhile { $0 != "=" } ?? TorrentUtils.infoHash(magnet) ?? magnet), name: a.txt,
                           size: li.first("td.sr-col-size").ownStr,
                           seeders: li.first("td.sr-col-seeders > span.sr-seed")?.own.uintLenient,
                           peers: li.first("td.sr-col-leechers > span.sr-leech")?.own.uintLenient, providerName: name,
                           uploadDate: li.first("td.sr-col-uploaded").ownStr.flatMap(TorrentDateParser.tryParseRelative),
                           category: li.first("td.sr-col-cat > a.sr-cat-badge").ownStr.map(Self.category),
                           detailsPageUrl: details, magnetUri: .available(magnet))
        }
    }
    static func category(_ raw: String) -> Category {
        switch raw {
        case "Anime": return .anime
        case "Apps": return .apps
        case "Games": return .games
        case "Movies": return .movies
        case "Music": return .music
        case "XXX": return .porn
        case "TV": return .series
        default: return .other
        }
    }
}

// MARK: XXXClub
final class XXXClub: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "xxxclub", name = "XXXClub", url = "https://xxxclub.to"
    let supportedCategories: Set<Category> = [.porn]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/torrents/search/all/\(query)"; return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/torrents/browse/all"; return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/torrents/top100"; return parse(try await net.getText(u), u)
    }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url) }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.first("div.browsetableinside, div.divtableinside")?.all("ul > li") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first(#"span:nth-child(2) > a[href^="/torrents/details"]"#), let details = a.at("abs:href").nonBlank else { return nil }
            return Torrent(id: torrentId(details), name: a.txt, size: li.first("span.siz").ownStr,
                           seeders: li.first("span.see")?.own.uint, peers: li.first("span.lee")?.own.uint, providerName: name,
                           uploadDate: li.first("span.adde").ownStr.flatMap { TorrentDateParser.parse($0, format: "dd MMM yyyy HH:mm:ss") },
                           category: .porn, detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
}

// MARK: XXXTracker
final class XXXTracker: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "xxxtracker", name = "XXXTracker", url = "https://xxxtor.com"
    let supportedCategories: Set<Category> = [.porn]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/b.php?search=\(query)"; return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/b.php"; return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/top"; return parse(try await net.getText(u), u)
    }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("table > tbody > tr") ?? []).dropFirst().compactMap { li -> Torrent? in
            guard let a = li.first("td:nth-child(2) > a:nth-child(3)"),
                  let magnet = li.first("td:nth-child(2) > a:nth-child(1)")?.at("href"),
                  let hash = TorrentUtils.infoHash(magnet) else { return nil }
            let date = li.first("td:nth-child(1)").ownStr
                .flatMap { TorrentDateParser.convertRussianMonthToEnglish($0.replacingOccurrences(of: "\u{00A0}", with: " ")) }
                .flatMap { TorrentDateParser.parse($0, format: "dd MMM yy") }
            return Torrent(id: torrentId(hash), name: a.own, size: li.first("td:nth-last-child(2)").ownStr,
                           seeders: li.first("td:nth-last-child(1) > span.green")?.own.trimmed.uint,
                           peers: li.first("td:nth-last-child(1) > span.red")?.own.trimmed.uint, providerName: name,
                           uploadDate: date, category: .porn, detailsPageUrl: a.at("abs:href"), magnetUri: .available(magnet),
                           fileDownloadLink: li.first("td:nth-child(2) > a:nth-child(2)")?.at("abs:href"))
        }
    }
}

// MARK: YTS
final class Yts: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "ytsmx", name = "Yts", url = "https://yts.bz"
    let supportedCategories: Set<Category> = [.movies]
    let enabledByDefault = true
    private let api = "https://movies-api.accel.li/api/v2"

    func search(query: String, category: Category) async throws -> [Torrent] {
        parse(try await net.getJson("\(api)/list_movies.json?query_term=\(query)&limit=50"))
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] { parse(try await net.getJson("\(api)/list_movies.json")) }
    func getTopTorrents(category: Category) async throws -> [Torrent] { try await getLatestTorrents(category: category) }

    private func parse(_ json: Any?) -> [Torrent] {
        ((json as? JObj)?.obj("data")?.objs("movies") ?? []).flatMap { m -> [Torrent] in
            guard let mid = m.long("id"), let title = m.str("title_long") else { return [] }
            let page = m.str("url")
            return m.objs("torrents").compactMap { t -> Torrent? in
                guard let hash = t.str("hash")?.lowercased() else { return nil }
                let n = "\(title) [\(t.str("quality") ?? "-")] [\(t.str("type") ?? "-")] [\(t.str("video_codec") ?? "-")]"
                return Torrent(id: torrentId(hash), name: n, size: t.str("size"), seeders: t.uint("seeds"), peers: t.uint("peers"),
                               providerName: name, uploadDate: t.long("date_uploaded_unix").map(TorrentDateParser.epochSecondToDate),
                               category: .movies, detailsPageUrl: page.map { "\($0)?movieid=\(mid)&infohash=\(hash)" },
                               magnetUri: .available(TorrentUtils.createMagnetUri(hash)))
            }
        }
    }
}

// MARK: 0Magnet
final class ZeroMagnet: SearchProvider, MagnetUriProvider {
    let id = "0magnet", name = "0Magnet", url = "https://9mag.net"
    let supportedCategories: Set<Category> = [.porn]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search?q=\(query)"
        return (Html.parse(try await net.getText(u), baseUrl: u)?.all("table.file-list > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let n = li.first("td.result-title > a")?.txt,
                  let details = li.first("td:nth-child(1) > a")?.at("abs:href").nonBlank else { return nil }
            return Torrent(id: torrentId(details), name: n,
                           size: li.first("td.result-meta > div:nth-child(1)").ownStr.map(FileSizeUtils.normalizeSize), providerName: name,
                           uploadDate: li.first("td.result-meta > div.result-date").ownStr.flatMap { TorrentDateParser.parse($0, format: "yyyy-MM-dd") },
                           category: .porn, detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
    func getMagnetUri(url: String) async throws -> String {
        guard let m = Html.parse(try await net.getText(url))?.first("input#input-magnet")?.at("value").nonBlank else {
            throw ProviderParseError(message: "Magnet não encontrado")
        }
        return m
    }
}
