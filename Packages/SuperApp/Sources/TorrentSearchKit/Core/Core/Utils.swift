import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

enum TorrentUtils {
    /// Trackers públicos (mesma lista do app original, ngosang/trackerslist).
    static let publicTrackers = [
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.demonoid.ch:6969/announce",
        "udp://open.demonii.com:1337/announce",
        "udp://open.stealth.si:80/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://explodie.org:6969/announce",
        "udp://tracker2.dler.org:80/announce",
        "udp://tracker.qu.ax:6969/announce",
        "udp://tracker.filemail.com:6969/announce",
        "udp://tracker.dler.org:6969/announce",
        "udp://tracker.bittor.pw:1337/announce",
        "udp://tracker.0x7c0.com:6969/announce",
        "udp://tracker-udp.gbitt.info:80/announce",
        "udp://run.publictracker.xyz:6969/announce",
        "udp://retracker01-msk-virt.corbina.net:80/announce",
        "udp://p4p.arenabg.com:1337/announce",
        "udp://opentracker.io:6969/announce",
        "udp://open.tracker.cl:1337/announce",
        "udp://leet-tracker.moe:1337/announce",
    ]
    private static let trackersParams = publicTrackers.map { "tr=\($0)" }.joined(separator: "&")
    private static let magnetPrefix = "magnet:?xt=urn:btih:"

    struct InvalidMagnet: Error {}

    static func getInfoHashFromMagnetUri(_ magnetUri: String) throws -> String {
        guard magnetUri.hasPrefix(magnetPrefix) else { throw InvalidMagnet() }
        let rest = magnetUri.dropFirst(magnetPrefix.count)
        return String(rest.prefix { $0 != "&" }).lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Variante que não lança erro (para uso em `??`).
    static func infoHash(_ magnetUri: String) -> String? { try? getInfoHashFromMagnetUri(magnetUri) }

    static func createMagnetUri(_ infoHash: String) -> String {
        "magnet:?xt=urn:btih:\(infoHash)&\(trackersParams)"
    }

    static func createTorrentId(providerId: String, sourceId: String) -> String {
        let digest = SHA256.hash(data: Data(sourceId.utf8))
        return "\(providerId):" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum FileSizeUtils {
    private static let KB: Double = 1024, MB = KB * 1024, GB = MB * 1024, TB = GB * 1024, PB = TB * 1024

    static func normalizeSize(_ size: String) -> String {
        var out = ""
        let chars = Array(size)
        for i in chars.indices {
            out.append(chars[i])
            if i < chars.count - 1, chars[i].isNumber, chars[i + 1].isLetter { out.append(" ") }
        }
        return out
    }

    static func formatBytes(_ bytes: Double) -> String {
        let (value, unit): (Double, String)
        if bytes >= PB { (value, unit) = (bytes / PB, "PB") }
        else if bytes >= TB { (value, unit) = (bytes / TB, "TB") }
        else if bytes >= GB { (value, unit) = (bytes / GB, "GB") }
        else if bytes >= MB { (value, unit) = (bytes / MB, "MB") }
        else if bytes >= KB { (value, unit) = (bytes / KB, "KB") }
        else { (value, unit) = (0, "B") }
        return String(format: "%.2f %@", locale: Locale(identifier: "en_US_POSIX"), value, unit)
    }

    static func formatBytes(_ bytes: String) -> String? { Double(bytes).map(formatBytes) }

    static func getBytes(_ formatted: String) -> Double {
        let (value, unit) = valueAndUnit(formatted)
        guard let v = Double(value.replacingOccurrences(of: ",", with: ".")) else { return 0 }
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "PB", "PiB": return v * PB
        case "TB", "TiB": return v * TB
        case "GB", "GiB": return v * GB
        case "MB", "MiB": return v * MB
        case "KB", "KiB": return v * KB
        default: return 0
        }
    }

    private static func valueAndUnit(_ s: String) -> (String, String) {
        if let sp = s.firstIndex(of: " ") {
            return (String(s[..<sp]), String(s[s.index(after: sp)...]))
        }
        guard let idx = s.firstIndex(where: { $0.isLetter }) else { return (s, "KB") }
        return (String(s[..<idx]), String(s[idx...]))
    }
}

enum TorrentDateParser {
    private static let utc = TimeZone(identifier: "UTC")!
    private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    private static func formatter(_ format: String) -> DateFormatter {
        lock.lock(); defer { lock.unlock() }
        if let f = cache[format] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = javaToICU(format)
        f.isLenient = false
        cache[format] = f
        return f
    }

    /// Converte os poucos símbolos que diferem entre Java e ICU.
    private static func javaToICU(_ p: String) -> String {
        p.replacingOccurrences(of: "uuuu", with: "yyyy")
    }

    static func parse(_ date: String, format: String) -> Date? {
        let d = date.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = formatter(format).date(from: d) { return r }
        // Java aceita maiúsculas/minúsculas; tenta capitalizado.
        return formatter(format).date(from: d.capitalized)
    }

    private static let relativeRegex = try! NSRegularExpression(
        pattern: #"\b(\d+(?:\.\d+)?)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|wk|wks|week|weeks|mo|mos|month|months|y|yr|yrs|year|years)\b\s*(ago)?\b"#,
        options: [.caseInsensitive])

    static func tryParseRelative(_ raw: String) -> Date? {
        var date = raw.trimmingCharacters(in: .whitespaces)
        if date.hasSuffix("+") { date.removeLast() }
        date = date.trimmingCharacters(in: .whitespaces)
        if let s = tryParseSpecialRelative(date) { return s }
        let ns = date as NSString
        guard let m = relativeRegex.firstMatch(in: date, range: NSRange(location: 0, length: ns.length)),
              let value = Double(ns.substring(with: m.range(at: 1))) else { return nil }
        let v = Double(Int64(value))
        let unit = ns.substring(with: m.range(at: 2)).lowercased()
        let seconds: Double
        switch unit {
        case "s", "sec", "secs", "second", "seconds": seconds = v
        case "m", "min", "mins", "minute", "minutes": seconds = v * 60
        case "h", "hr", "hrs", "hour", "hours": seconds = v * 3600
        case "d", "day", "days": seconds = v * 86400
        case "w", "wk", "wks", "week", "weeks": seconds = v * 7 * 86400
        case "mo", "mos", "month", "months": seconds = v * 30 * 86400
        case "y", "yr", "yrs", "year", "years": seconds = v * 365 * 86400
        default: return nil
        }
        return Date().addingTimeInterval(-seconds)
    }

    static func tryParseSpecialRelative(_ date: String) -> Date? {
        switch date.lowercased() {
        case "today", "just now", "moments ago": return Date()
        case "yesterday": return getYesterdayDate()
        case "last week": return Date().addingTimeInterval(-7 * 86400)
        case "last month": return Date().addingTimeInterval(-30 * 86400)
        case "last year": return Date().addingTimeInterval(-365 * 86400)
        default: return nil
        }
    }

    static func tryParseTime(_ time: String) -> Date? {
        guard let t = formatter("h:m a").date(from: time.uppercased()) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        let comps = cal.dateComponents([.hour, .minute], from: t)
        return cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: Date())
    }

    static func epochSecondToDate(_ s: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(s)) }

    static func parseIso(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }

    static func parseRFC1123(_ s: String) -> Date? {
        parse(s, format: "EEE, dd MMM yyyy HH:mm:ss zzz") ?? parse(s, format: "EEE, d MMM yyyy HH:mm:ss Z")
    }

    static func getTodayDate() -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        return cal.startOfDay(for: Date())
    }

    static func getYesterdayDate() -> Date { getTodayDate().addingTimeInterval(-86400) }

    static func getCurrentYear() -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        return cal.component(.year, from: Date())
    }

    private static let russianMonths = [
        "Янв": "Jan", "Фев": "Feb", "Мар": "Mar", "Апр": "Apr", "Май": "May", "Июн": "Jun",
        "Июл": "Jul", "Авг": "Aug", "Сен": "Sep", "Окт": "Oct", "Ноя": "Nov", "Дек": "Dec",
    ]

    static func convertRussianMonthToEnglish(_ date: String) -> String? {
        let parts = date.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3, let m = russianMonths[parts[1]] else { return nil }
        return "\(parts[0]) \(m) \(parts[2])"
    }
}

extension String {
    /// Equivalente ao `Uri.encode` do Android (espaço vira %20).
    var uriEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "_-!.~'()*")
        // CharacterSet.alphanumerics inclui letras não ASCII; restringe a ASCII.
        let ascii = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-!.~'()*")
        return addingPercentEncoding(withAllowedCharacters: ascii) ?? self
    }

    var uriDecoded: String { removingPercentEncoding ?? self }

    func removingPrefix(_ p: String) -> String { hasPrefix(p) ? String(dropFirst(p.count)) : self }
    func removingSuffix(_ s: String) -> String { hasSuffix(s) ? String(dropLast(s.count)) : self }
    func removingSurrounding(_ p: String, _ s: String) -> String {
        (hasPrefix(p) && hasSuffix(s) && count >= p.count + s.count) ? String(dropFirst(p.count).dropLast(s.count)) : self
    }
    func removingSurrounding(_ d: String) -> String { removingSurrounding(d, d) }
    func substringAfter(_ d: String) -> String {
        guard let r = range(of: d) else { return self }
        return String(self[r.upperBound...])
    }
    func substringAfterLast(_ d: String) -> String {
        guard let r = range(of: d, options: .backwards) else { return self }
        return String(self[r.upperBound...])
    }
    func substringBefore(_ d: String) -> String {
        guard let r = range(of: d) else { return self }
        return String(self[..<r.lowerBound])
    }
    func substringBeforeLast(_ d: String) -> String {
        guard let r = range(of: d, options: .backwards) else { return self }
        return String(self[..<r.lowerBound])
    }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonBlank: String? { trimmed.isEmpty ? nil : self }
    /// Equivalente ao `toUIntOrNull()` do Kotlin.
    var uint: Int? {
        let t = self
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(t)
    }
    /// Remove separadores de milhar antes de converter.
    var uintLenient: Int? { replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "").trimmed.uint }
    func takeWhile(_ p: (Character) -> Bool) -> String { String(prefix(while: p)) }
    func takeLastWhile(_ p: (Character) -> Bool) -> String { String(reversed().prefix(while: p).reversed()) }
    var lines: [String] { components(separatedBy: .newlines) }

    /// Primeiro grupo de captura de uma regex.
    func firstMatch(_ pattern: String, group: Int = 1, options: NSRegularExpression.Options = []) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group, m.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    func allGroups(_ pattern: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map {
            m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0))
        }
    }

    func matches(_ pattern: String) -> Bool { firstMatch("(" + pattern + ")") != nil }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
