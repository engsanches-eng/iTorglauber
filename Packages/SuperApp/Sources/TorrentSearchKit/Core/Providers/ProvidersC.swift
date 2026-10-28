import Foundation
import SwiftSoup

// Portado de: LimeTorrents, LinuxTracker, MegaPeer, Mikan, MyPornClub, NekoBT.

/// Busca o primeiro link magnet de uma página (padrão usado por vários buscadores).
func fetchFirstMagnet(_ net: Net, _ url: String, selector: String = #"a[href^="magnet:?"]"#) async throws -> String {
    guard let m = Html.parse(try await net.getText(url), baseUrl: url)?.first(selector)?.at("href").nonBlank else {
        throw ProviderParseError(message: "Magnet não encontrado")
    }
    return m
}

// MARK: LimeTorrents
final class LimeTorrents: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "limetorrents", name = "LimeTorrents", url = "https://limetorrents.fun"
    let supportedCategories: Set<Category> = [.anime, .apps, .games, .movies, .music, .series, .other]
    let safety: ProviderSafety = .unsafe(reason: L("Não é inseguro de fato, mas ignora a categoria escolhida. Escolha com cuidado."))
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search/\(searchString(category))/\(query)/date/1/"
        return parse(try await net.getText(u), u, nil)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        guard supportedCategories.contains(category), let b = browseString(category) else { return [] }
        let u = "\(url)/browse-torrents/\(b)/"
        return parse(try await net.getText(u), u, category)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        guard supportedCategories.contains(category), let b = browseString(category) else { return [] }
        let u = "\(url)/cat_top/16/\(b)/"
        return parse(try await net.getText(u), u, category)
    }
    private func searchString(_ c: Category) -> String {
        switch c {
        case .all, .books, .porn: return "all"
        case .anime: return "anime"
        case .apps: return "applications"
        case .games: return "games"
        case .movies: return "movies"
        case .music: return "music"
        case .series: return "tv"
        case .other: return "other"
        }
    }
    private func browseString(_ c: Category) -> String? {
        switch c {
        case .all, .porn: return nil
        case .anime: return "Anime"
        case .apps: return "Applications"
        case .books: return "Other-E-books"
        case .games: return "Games"
        case .movies: return "Movies"
        case .music: return "Music"
        case .series: return "TV-shows"
        case .other: return "Other"
        }
    }
    private func parse(_ html: String, _ pageUrl: String, _ searchCategory: Category?) -> [Torrent] {
        let nameSel = "td:nth-child(1) > div.tt-name > a:nth-child(2)"
        return (Html.parse(html, baseUrl: pageUrl)?.all(".table2 > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first(nameSel),
                  let dl = li.first("td:nth-child(1) > div.tt-name > a:nth-child(1)")?.at("href") else { return nil }
            let hash = dl.removingPrefix("http://itorrents.net/torrent/").takeWhile { $0 != "." }.lowercased()
            var rawDate: String?, rawCat: String?
            if let t = li.first("td:nth-child(2)")?.own {
                if t.contains("- in") {
                    let parts = t.split(separator: "-", maxSplits: 1).map { String($0).trimmed }
                    rawDate = parts[safe: 0]
                    rawCat = parts[safe: 1]?.removingPrefix("in ").removingSuffix(".")
                } else { rawDate = t.trimmed }
            }
            return Torrent(id: torrentId(hash), name: a.own, size: li.first("td:nth-child(3)").ownStr,
                           seeders: li.first("td.tdseed")?.own.uintLenient, peers: li.first("td.tdleech")?.own.uintLenient,
                           providerName: name, uploadDate: rawDate.flatMap(TorrentDateParser.tryParseRelative),
                           category: rawCat.map(Self.category) ?? searchCategory, detailsPageUrl: a.at("abs:href"),
                           magnetUri: .available(TorrentUtils.createMagnetUri(hash)), fileDownloadLink: dl)
        }
    }
    static func category(_ raw: String) -> Category {
        switch raw {
        case "TV": return .series
        case "Movie": return .movies
        case "Music": return .music
        case "App": return .apps
        case "E-book": return .books
        case "Anime": return .anime
        case "Games": return .games
        default: return .other
        }
    }
}

// MARK: LinuxTracker
final class LinuxTracker: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "linuxtracker", name = "LinuxTracker", url = "https://linuxtracker.org"
    let supportedCategories: Set<Category> = [.apps]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/index.php?page=torrents&search=\(query)&category=0&active=0"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/torrents/"
        return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] { try await getLatestTorrents(category: category) }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url) }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("table.torrent-table > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("td.torrent-name-cell > a.torrent-name"), let details = a.at("abs:href").nonBlank else { return nil }
            return Torrent(id: torrentId(details.removingSuffix("/").takeLastWhile { $0 != "/" }), name: a.own,
                           size: li.first("td:nth-child(4)").ownStr, seeders: li.first("td.seeds > strong")?.own.uint,
                           peers: li.first("td.leeches > strong")?.own.uint, providerName: name,
                           uploadDate: li.first("td:nth-child(3)").ownStr.flatMap { TorrentDateParser.parse($0.trimmed, format: "MMM d, yyyy") },
                           category: .apps, detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
}

// MARK: MegaPeer
final class MegaPeer: SearchProvider, MagnetUriProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "megapeer", name = "MegaPeer", url = "https://megapeer.vip"
    let supportedCategories: Set<Category> = [.apps, .books, .games, .movies, .music, .other, .series]
    let enabledByDefault = false
    private let categoryMap: [Category: Int] = [.all: 0, .apps: 29, .books: 52, .games: 28, .movies: 80, .music: 94, .other: 59, .series: 6]

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/browse.php?search=\(query)&age=&cat=\(categoryMap[category] ?? 0)&stype=0&sort=0&ascdesc=0"
        return parse(try await net.getText(u), u)
    }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url, selector: #"a[href^="magnet:?xt="]"#) }
    func getLatestTorrents(category: Category) async throws -> [Torrent] { parse(try await net.getText(url), url) }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/top"
        return parse(try await net.getText(u), u)
    }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("div#index > table > tbody > tr.table_fon") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("td:nth-child(2) > a:nth-child(2)"), let details = a.at("abs:href").nonBlank else { return nil }
            let date = li.first("td:nth-child(1)").ownStr
                .map { $0.replacingOccurrences(of: "Мая", with: "Май") }
                .flatMap(TorrentDateParser.convertRussianMonthToEnglish)
                .flatMap { TorrentDateParser.parse($0, format: "d MMM yy") }
            return Torrent(id: torrentId(details), name: a.own, size: li.first("td:nth-child(3)").ownStr,
                           seeders: li.first("td:nth-child(4) > font:nth-child(2)")?.own.uint,
                           peers: li.first("td:nth-child(4) > font:nth-child(4)")?.own.uint, providerName: name,
                           uploadDate: date, detailsPageUrl: details, magnetUri: .requiresFetch(details),
                           fileDownloadLink: li.first("td:nth-child(2) > a:nth-child(1)")?.at("abs:href"))
        }
    }
}

// MARK: Mikan
final class Mikan: SearchProvider {
    let id = "mikanproject", name = "Mikan", url = "https://mikanani.me"
    let supportedCategories: Set<Category> = [.anime]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/Home/Search?searchstr=\(query)"
        return (Html.parse(try await net.getText(u), baseUrl: u)?.all("tr.js-search-results-row") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("td:nth-child(2) > a:nth-child(1)"),
                  let magnet = li.first("td:nth-child(2) > a[data-clipboard-text]")?.at("data-clipboard-text"),
                  let hash = TorrentUtils.infoHash(magnet) else { return nil }
            return Torrent(id: torrentId(hash), name: a.own, size: li.first("td:nth-child(3)").ownStr.map(FileSizeUtils.normalizeSize),
                           providerName: name,
                           uploadDate: li.first("td:nth-child(4)").ownStr.flatMap { TorrentDateParser.parse($0, format: "yyyy/MM/dd HH:mm") },
                           category: .anime, detailsPageUrl: a.at("abs:href"), magnetUri: .available(magnet),
                           fileDownloadLink: li.first("td:nth-child(5) > a")?.at("abs:href"))
        }
    }
}

// MARK: MyPornClub
final class MyPornClub: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "mypornclub", name = "MyPornClub", url = "https://myporn.club"
    let supportedCategories: Set<Category> = [.porn]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/s/\(query.trimmed.replacingOccurrences(of: "%20", with: "-"))/seeders"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/ts/latest/alltime"; return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/ts/hits/alltime"; return parse(try await net.getText(u), u)
    }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url, selector: "a.md_btn") }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("div.torrents_list > div.torrent_element") ?? []).compactMap { li -> Torrent? in
            guard let details = li.first("div.torrent_element_text_div > a:nth-child(2)")?.at("abs:href").nonBlank,
                  let n = li.first("div.torrent_element_text_div > a:nth-child(2) > span.torrent_element_text_span")?.own else { return nil }
            let rid = details.takeWhile { $0 != "?" }.takeLastWhile { $0 != "/" }
            return Torrent(id: torrentId(rid), name: n,
                           size: li.first("div.torrent_element_info > span.teiv:nth-child(4)").ownStr.map { $0.uppercased() },
                           seeders: li.first("div.torrent_element_info > span.teiv.teiv_seeders")?.own.uint,
                           peers: li.first("div.torrent_element_info > span.teiv.teiv_leechers")?.own.uint, providerName: name,
                           uploadDate: li.first("div.torrent_element_info > span.teiv:nth-child(2)").textStr.flatMap(TorrentDateParser.tryParseRelative),
                           category: .porn, detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
}

// MARK: NekoBT
final class NekoBT: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "nekobt", name = "NekoBT", url = "https://nekobt.to"
    let supportedCategories: Set<Category> = [.anime]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search?query=\(query)"; return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/search?sort-by=latest"; return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/search?sort-by=seeders"; return parse(try await net.getText(u), u)
    }
    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        let nameSel = "td:nth-child(3) > div:nth-child(1) > div > a"
        return (Html.parse(html, baseUrl: pageUrl)?.all("table.table > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let n = li.first(nameSel)?.first("span > span:nth-child(1)")?.own,
                  let magnet = li.first("td:nth-child(4) > div > a:nth-child(1)")?.at("href"), !magnet.isEmpty else { return nil }
            let details = li.first(nameSel).attrStr("abs:href")
            return Torrent(id: torrentId(details?.takeLastWhile { $0 != "/" }.nonBlank ?? TorrentUtils.infoHash(magnet) ?? magnet), name: n,
                           size: li.first("td:nth-child(5) > span").ownStr, seeders: li.first("td:nth-child(7) > span")?.own.uint,
                           peers: li.first("td:nth-child(8) > span")?.own.uint, providerName: name,
                           uploadDate: li.first("td:nth-child(6) > span").ownStr.flatMap { TorrentDateParser.parse($0, format: "yyyy-MM-dd HH:mm:ss") },
                           category: .anime, detailsPageUrl: details, magnetUri: .available(magnet),
                           fileDownloadLink: li.first("td:nth-child(4) > div > a:nth-child(2)")?.at("abs:href"))
        }
    }
}
