import Foundation
import SwiftSoup

// Portado de: NoNameClub, Nyaa, OxTorrent, Rutor, SubsPlease, Sukebei.

// MARK: NoNameClub
final class NoNameClub: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "nonameclub", name = "NoNameClub", url = "https://nnmclub.to"
    let supportedCategories: Set<Category> = [.anime, .apps, .books, .games, .movies, .music, .series, .other]
    let enabledByDefault = false
    private let categoryToId: [Category: Int] = [.anime: 615, .apps: 512, .books: 434, .games: 410, .movies: 216, .music: 313, .series: 768, .other: 48]

    func search(query: String, category: Category) async throws -> [Torrent] {
        // A busca vai no formulário; o texto chega codificado, então decodifica antes.
        try await run(query.uriDecoded, category, criteria: 2, date: -1)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] { try await run(nil, category, criteria: 1, date: 1) }
    func getTopTorrents(category: Category) async throws -> [Torrent] { try await run(nil, category, criteria: 10, date: -1) }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url, selector: #"a[href^="magnet:?xt="]"#) }

    private func run(_ query: String?, _ category: Category, criteria: Int, date: Int) async throws -> [Torrent] {
        let u = "\(url)/forum/tracker.php"
        let form: [(String, String)] = [
            ("f[]", categoryToId[category].map(String.init) ?? "-1"), ("o", String(criteria)), ("s", "2"),
            ("tm", String(date)), ("shf", "1"), ("ta", "-1"), ("sns", "-1"), ("sds", "4"), ("nm", query ?? ""), ("submit", "Поиск"),
        ]
        let html = try await net.submitForm(u, form: form)
        let sel = #"table.forumline.tablesorter > tbody > tr:has(a[href^="viewtopic.php?t="]):has(a[href^="download.php?id="])"#
        return (Html.parse(html, baseUrl: u)?.all(sel) ?? []).compactMap { li -> Torrent? in
            guard let details = li.first(#"a[href^="viewtopic.php?t="]"#)?.at("abs:href").nonBlank,
                  let n = li.first(#"a[href^="viewtopic.php?t="] > b"#)?.own else { return nil }
            let catId = li.first(#"a[href^="tracker.php?f="]"#).attrStr("href")
                .map { $0.removingPrefix("tracker.php?f=").takeWhile { $0 != "&" } }
            return Torrent(id: torrentId(details.substringAfterLast("=").nonBlank ?? details), name: n,
                           size: li.first("td:nth-child(6) > u").ownStr.flatMap { FileSizeUtils.formatBytes($0) },
                           seeders: li.first("td.seedmed > b")?.own.uint, peers: li.first("td.leechmed > b")?.own.uint,
                           providerName: name,
                           uploadDate: li.first("td:last-child > u").ownStr.flatMap { Int64($0) }.map(TorrentDateParser.epochSecondToDate),
                           category: catId.map(Self.category), detailsPageUrl: details, magnetUri: .requiresFetch(details),
                           fileDownloadLink: li.first(#"a[href^="download.php?id="]"#)?.at("abs:href"))
        }
    }

    // IDs do Jackett (noname-club.yml), iguais aos do app original.
    private static let idMap: [String: Category] = {
        var m: [String: Category] = [:]
        func add(_ c: Category, _ ids: String) { ids.split(separator: " ").forEach { m[String($0)] = c } }
        add(.other, "48 925 872")
        add(.series, "724 725 729 731 1345 733 1346 1329 1330 1331 1332 1340 658 890 1336 1337 1338 1339 660 232 734 742 735 738 967 907 739 1109 736 737 898 935 871 973 960 1239 740 741")
        add(.apps, "503 504 506 763 1335 1241 1023 717 509 508 510 1254 1042 511 916 512 561 1284 562 513 514 515 516 517 518 519 520 521 522 523 524 532 533 535 530 529 525 526 527 545 764 765 820 552 553 554 550 549 548")
        add(.movies, "216 270 218 219 954 217 1293 1298 318 320 677 1177 319 678 885 908 1310 909 910 911 912 220 221 222 882 889 224 225 226 227 1296 891 1299 682 694 884 1211 693 913 228 1150 1311 1313 1312 256 257 258 883 955 905 271 1210 264 265 272 1262 266 1294")
        add(.series, "1219 1221 1220 722 768 1344 779 1288 787 1141 777 786 776 785 775 1265 1242 1140 782 773 1142 772 771 783 1144 804 1290 1300 784 774 922 770 1320 780 781 1322 769 799 800 791 793 794 796 795 713 706 577 894 578 580 579 953 581 806 714 761 809 924 812 576 590 591 588 589 598 652 599 959 956 597 593 594 819 595 587 584 586 585 600 596 1295 614 603 1308 1309 1206 1194 1062 974 609 1263 951 975 608 607 606 750 605 604 950 610 613 612 653 654 611 656 437 466 1319 463 958 1223 467 464 465 1348 469")
        add(.anime, "615 616 617 648 619 620 623 622 621 632 624 627 626 625 644 628 635 634 638 646 645 639 640")
        add(.books, "432 755 481 557 442 441 875 1176 444 443 440 1199 433 447 445 817 818 434 1349 957 931 1152 455 453 1063 452 451 449 1153 1347 482 483 484 1343 438 485 473 472 471 895 470 896 480 439 477 476 475 474 886 478 486 490 657 489 488 487 1198 1227 893 491 767 299 887 301 1334 300 1341 492 558 1173 1174 1171 662 1175 1172 933 815 1170 398 816")
        add(.music, "313 1291 680 1149 429 681 330 1256 1285 370 1260 371 1261 375 1259 374 1257 373 1258 372 1160 876 1255 376 326 1352 359 358 1353 1188 1189 328 1370 1180 1181 364 363 1179 879 322 1350 962 333 1356 965 336 1362 337 338 1351 963 334 1357 961 332 325 1354 1355 1165 1166 1168 1167 1162 352 1164 1163 1161 353 324 1327 1328 1325 1326 1365 1366 1323 1324 976 346 1363 977 345 349 1243 347 979 673 671 1224 1225 1367 980 672 1316 1317 1364 981 344 1368 983 984 982 348 674 323 1369 1187 339 1186 340 1185 341 329 1361 369 368 1218 365 1217 366 1215 1216 1213 367 331 1358 1157 711 1159 378 1359 1158 379 380 1178 1360 361 360 327 1184 824 1182 354 877 1183 1190 917 1096 1097 1095")
        add(.games, "410 411 412 1008 415 746 428 1009 413 414 1010 1012 1014 416 1013 1015 268 1016 1041 1018 1017 972 971 970 969 968 1146 418 1061 1060 1059 1058 1057 1056 1054 1053 1052 1051 1050 1049 1048 1047 1046 1045 1044 382 390 387 388 1264 1318 385 386 848 1321 383 384 1292 389 391 417 1193 1192")
        return m
    }()
    static func category(_ id: String) -> Category { idMap[id] ?? .other }
}

// MARK: Nyaa e Sukebei (mesmo layout de página)
private func parseNyaaTable(_ html: String, _ pageUrl: String, _ p: SearchProvider, fixedCategory: Category?) -> [Torrent] {
    (Html.parse(html, baseUrl: pageUrl)?.all("table.torrent-list > tbody > tr") ?? []).compactMap { li -> Torrent? in
        guard let a = li.first("td:nth-child(2) > a:not(.comments)"),
              let magnet = li.first("td:nth-child(3) > a:nth-child(2)")?.at("href"),
              let hash = TorrentUtils.infoHash(magnet) else { return nil }
        let details = a.at("abs:href").nonBlank
        let cat = fixedCategory ?? li.first("td:nth-child(1) > a").attrStr("href").map { Nyaa.category($0.removingPrefix("/?c=")) }
        return Torrent(id: p.torrentId(details?.takeLastWhile { $0 != "/" } ?? hash), name: a.own,
                       size: li.first("td:nth-child(4)").ownStr, seeders: li.first("td:nth-child(6)")?.own.uint,
                       peers: li.first("td:nth-child(7)")?.own.uint, providerName: p.name,
                       uploadDate: li.first("td:nth-child(5)").attrStr("data-timestamp").flatMap { Int64($0) }.map(TorrentDateParser.epochSecondToDate),
                       category: cat, detailsPageUrl: details, magnetUri: .available(magnet),
                       fileDownloadLink: li.first("td:nth-child(3) > a:nth-child(1)")?.at("abs:href"))
    }
}

final class Nyaa: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "nyaasi", name = "Nyaa", url = "https://nyaa.si"
    let supportedCategories: Set<Category> = [.anime, .apps, .books, .games, .music, .series]
    let enabledByDefault = true
    private let categoryMap: [Category: String] = [.all: "0_0", .anime: "1_0", .apps: "6_1", .books: "3_0", .games: "6_2", .music: "2_0", .series: "4_0"]

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/?f=0&c=\(categoryMap[category] ?? "0_0")&q=\(query)"
        return parseNyaaTable(try await net.getText(u), u, self, fixedCategory: nil)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)?c=\(categoryMap[category] ?? "0_0")"
        return parseNyaaTable(try await net.getText(u), u, self, fixedCategory: nil)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)?s=seeders&o=desc&c=\(categoryMap[category] ?? "0_0")"
        return parseNyaaTable(try await net.getText(u), u, self, fixedCategory: nil)
    }
    static func category(_ id: String) -> Category {
        switch id {
        case "1_0", "1_1", "1_2", "1_3", "1_4": return .anime
        case "2_0", "2_1", "2_2": return .music
        case "3_0", "3_1", "3_2", "3_3": return .books
        case "4_0", "4_1", "4_2", "4_3", "4_4": return .series
        case "6_0", "6_1": return .apps
        case "6_2": return .games
        default: return .other
        }
    }
}

final class Sukebei: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "sukebeinyaa", name = "Sukebei", url = "https://sukebei.nyaa.si"
    let supportedCategories: Set<Category> = [.porn]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/?f=0&c=0_0&q=\(query)"
        return parseNyaaTable(try await net.getText(u), u, self, fixedCategory: .porn)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        parseNyaaTable(try await net.getText(url), url, self, fixedCategory: .porn)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/?s=seeders&o=desc"
        return parseNyaaTable(try await net.getText(u), u, self, fixedCategory: .porn)
    }
}

// MARK: OxTorrent
final class OxTorrent: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider, MagnetUriProvider {
    let id = "oxtorrent", name = "OxTorrent", url = "https://oxtorrent.co"
    let supportedCategories: Set<Category> = [.apps, .books, .games, .movies, .music, .series]
    let isCloudflareProtected = true
    let enabledByDefault = false
    private let categoryMap: [Category: String] = [.apps: "logiciels", .books: "ebook", .games: "jeux-pc", .movies: "films", .music: "musique", .series: "series"]

    func search(query: String, category: Category) async throws -> [Torrent] {
        var u = "\(url)/recherche"
        if let c = categoryMap[category] { u += "/\(c)" }
        u += "/\(query)"
        return parse(try await net.getText(u), u)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        guard let slug = categoryMap[category] else { return [] }
        let u = "\(url)/torrents/\(slug)"
        return parse(try await net.getText(u), u)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/top"; return parse(try await net.getText(u), u)
    }
    func getMagnetUri(url: String) async throws -> String { try await fetchFirstMagnet(net, url, selector: "div.btn-magnet > a") }

    private func parse(_ html: String, _ pageUrl: String) -> [Torrent] {
        (Html.parse(html, baseUrl: pageUrl)?.all("table > tbody > tr") ?? []).compactMap { li -> Torrent? in
            guard let a = li.first("td:nth-child(1) > a"), let details = a.at("abs:href").nonBlank, !a.own.isEmpty else { return nil }
            let cls = (try? li.first("td:nth-child(1) > i")?.className()) ?? nil
            return Torrent(id: torrentId(details), name: a.own, size: li.first("td:nth-child(2)").ownStr,
                           seeders: li.first("td:nth-child(3)")?.own.uint, peers: li.first("td:nth-child(4)")?.own.uint,
                           providerName: name, category: cls.map(Self.category), detailsPageUrl: details, magnetUri: .requiresFetch(details))
        }
    }
    static func category(_ raw: String) -> Category {
        switch raw {
        case "ebook": return .books
        case "films": return .movies
        case "jeux-consoles", "jeux-pc": return .games
        case "logiciels": return .apps
        case "musique": return .music
        case "series": return .series
        default: return .other
        }
    }
}

// MARK: Rutor
final class Rutor: SearchProvider, LatestTorrentsProvider, TopTorrentsProvider {
    let id = "rutorinfo", name = "Rutor", url = "https://rutor.info"
    let supportedCategories: Set<Category> = [.anime, .apps, .books, .games, .movies, .music, .other, .series]
    let enabledByDefault = false
    private let categoryMap: [Category: Int] = [.all: 0, .anime: 10, .apps: 9, .books: 11, .games: 8, .movies: 1, .music: 2, .other: 3, .series: 4]

    func search(query: String, category: Category) async throws -> [Torrent] {
        let u = "\(url)/search/0/\(categoryMap[category] ?? 0)/010/2/\(query)"
        return parse(try await net.getText(u), u, category)
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/browse/0/\(categoryMap[category] ?? 0)/0/0"
        return parse(try await net.getText(u), u, category)
    }
    func getTopTorrents(category: Category) async throws -> [Torrent] {
        let u = "\(url)/top"; return parse(try await net.getText(u), u, category)
    }
    private func parse(_ html: String, _ pageUrl: String, _ searchCategory: Category) -> [Torrent] {
        var seen = Set<String>()
        return (Html.parse(html, baseUrl: pageUrl)?.all("div#index > table > tbody > tr") ?? []).dropFirst().compactMap { li -> Torrent? in
            guard let a = li.first("td:nth-child(2) > a:nth-child(3)"),
                  let magnet = li.first("td:nth-child(2) > a:nth-child(2)")?.at("href"),
                  let hash = TorrentUtils.infoHash(magnet) else { return nil }
            let tid = torrentId(hash)
            guard seen.insert(tid).inserted else { return nil }
            let date = li.first("td:nth-child(1)").ownStr
                .flatMap { TorrentDateParser.convertRussianMonthToEnglish($0.replacingOccurrences(of: "\u{00A0}", with: " ")) }
                .flatMap { TorrentDateParser.parse($0, format: "dd MMM yy") }
            return Torrent(id: tid, name: a.own, size: li.first("td:nth-last-child(2)").ownStr.map { $0.replacingOccurrences(of: "\u{00A0}", with: " ") },
                           seeders: li.first("td:nth-last-child(1) > span:nth-child(1)")?.own.trimmed.uint,
                           peers: li.first("td:nth-last-child(1) > span:nth-child(3)")?.own.trimmed.uint, providerName: name,
                           uploadDate: date, category: searchCategory == .all ? nil : searchCategory,
                           detailsPageUrl: a.at("abs:href"), magnetUri: .available(magnet),
                           fileDownloadLink: li.first("td:nth-child(2) > a:nth-child(1)")?.at("abs:href"))
        }
    }
}

// MARK: SubsPlease
final class SubsPlease: SearchProvider, LatestTorrentsProvider {
    let id = "subsplease", name = "SubsPlease", url = "https://subsplease.org"
    let supportedCategories: Set<Category> = [.anime]
    let enabledByDefault = false

    func search(query: String, category: Category) async throws -> [Torrent] {
        parse(try await net.getJson("\(url)/api?f=search&tz=$&s=\(query)"))
    }
    func getLatestTorrents(category: Category) async throws -> [Torrent] {
        parse(try await net.getJson("\(url)/api/?f=latest&tz=$"))
    }
    private func parse(_ json: Any?) -> [Torrent] {
        guard let root = json as? JObj else { return [] }
        return root.sorted { $0.key < $1.key }.flatMap { (show, value) -> [Torrent] in
            guard let anime = value as? JObj else { return [] }
            let date = anime.str("release_date").flatMap(TorrentDateParser.parseRFC1123)
            let page = anime.str("page").map { "\(url)/\($0)" }
            let ep = anime.str("episode") ?? ""
            return anime.objs("downloads").compactMap { d -> Torrent? in
                guard let magnet = d.str("magnet"), let hash = TorrentUtils.infoHash(magnet) else { return nil }
                let res = d.str("res") ?? ""
                let size = magnet.substringAfter("?").split(separator: "&").first { $0.hasPrefix("xl=") }
                    .flatMap { FileSizeUtils.formatBytes(String($0.dropFirst(3))) }
                return Torrent(id: torrentId(hash), name: "\(show) [\(res)p]", size: size, providerName: name, uploadDate: date,
                               category: .anime, detailsPageUrl: page.map { "\($0)?ep=\(ep)&res=\(res)" }, magnetUri: .available(magnet))
            }
        }
    }
}
