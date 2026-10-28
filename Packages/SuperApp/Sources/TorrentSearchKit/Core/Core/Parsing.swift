import Foundation
import SwiftSoup

// MARK: - JSON (equivalente ao JsonExt.kt)

typealias JObj = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String? {
        switch self[k] {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
    func long(_ k: String) -> Int64? {
        switch self[k] {
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s)
        default: return nil
        }
    }
    func uint(_ k: String) -> Int? {
        switch self[k] {
        case let n as NSNumber: let v = n.intValue; return v >= 0 ? v : nil
        case let s as String: return s.uint
        default: return nil
        }
    }
    func double(_ k: String) -> Double? {
        switch self[k] {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
    func bool(_ k: String) -> Bool? { (self[k] as? NSNumber)?.boolValue }
    func obj(_ k: String) -> JObj? { self[k] as? JObj }
    func arr(_ k: String) -> [Any]? { self[k] as? [Any] }
    func objs(_ k: String) -> [JObj] { (self[k] as? [Any])?.compactMap { $0 as? JObj } ?? [] }
}

func jsonObjects(_ any: Any?) -> [JObj] { (any as? [Any])?.compactMap { $0 as? JObj } ?? [] }

// MARK: - HTML (atalhos sobre o SwiftSoup, no estilo do Jsoup)

enum Html {
    static func parse(_ html: String, baseUrl: String = "") -> Document? {
        try? SwiftSoup.parse(html, baseUrl)
    }
    static func parseXml(_ xml: String, baseUrl: String = "") -> Document? {
        try? SwiftSoup.parse(xml, baseUrl, Parser.xmlParser())
    }
}

extension Element {
    func all(_ css: String) -> [Element] { (try? select(css).array()) ?? [] }
    func first(_ css: String) -> Element? { try? select(css).first() }
    var txt: String { (try? text()) ?? "" }
    var own: String { ownText() }
    func at(_ name: String) -> String { (try? attr(name)) ?? "" }
    func has(_ name: String) -> Bool { hasAttr(name) }
    var inner: String { (try? html()) ?? "" }
    var nextEl: Element? { try? nextElementSibling() }
    var prevEl: Element? { try? previousElementSibling() }
    var kids: [Element] { children().array() }
    var dataText: String { data() }
    /// Texto preservando quebras de linha (equivalente a `wholeText()` do Jsoup).
    var wholeText: String {
        var out = ""
        func walk(_ n: Node) {
            if let t = n as? TextNode { out += t.getWholeText() }
            else if let e = n as? Element {
                if e.tagName() == "br" { out += "\n" }
                e.getChildNodes().forEach(walk)
            }
        }
        getChildNodes().forEach(walk)
        return out
    }
    func abs(_ name: String) -> String { (try? absUrl(name)) ?? "" }
}

extension Document {
    func firstText(_ css: String) -> String? { first(css)?.txt }
}

extension Optional where Wrapped == String {
    /// Converte "" em nil, como `takeIf { it.isNotBlank() }`.
    var nonBlank: String? { self.flatMap { $0.trimmed.isEmpty ? nil : $0 } }
}

extension Optional where Wrapped == Element {
    /// `ownText()` do elemento, ou nil se o elemento não existir.
    var ownStr: String? { self?.ownText() }
    /// `text()` do elemento, ou nil se o elemento não existir.
    var textStr: String? { self.map { $0.txt } }
    func attrStr(_ name: String) -> String? { self.map { $0.at(name) } }
}
