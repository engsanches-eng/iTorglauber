import Foundation

/// Idioma de legenda no formato do OpenSubtitles (ex.: "pt-br", "en").
struct SubtitleLanguage: Hashable, Identifiable, Codable {
    let code: String
    var id: String { code }

    init(_ code: String) { self.code = code.lowercased() }

    /// Nome no idioma do aparelho, ex.: "Português (Brasil)".
    var name: String {
        let ident: String
        switch code {
        case "pt-br": ident = "pt_BR"
        case "pt-pt": ident = "pt_PT"
        case "zh-cn": ident = "zh_Hans"
        case "zh-tw": ident = "zh_Hant"
        case "pob": ident = "pt_BR"
        default: ident = code.replacingOccurrences(of: "-", with: "_")
        }
        let raw = Locale.current.localizedString(forIdentifier: ident) ?? code
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    /// Sufixo usado no nome do arquivo quando o ajuste pede o idioma (ex.: "pt-BR").
    var fileTag: String {
        let parts = code.split(separator: "-")
        guard parts.count == 2 else { return code }
        return "\(parts[0])-\(parts[1].uppercased())"
    }

    static let portugueseBR = SubtitleLanguage("pt-br")
    static let english = SubtitleLanguage("en")

    /// Idiomas oferecidos nos ajustes (os mais usados no OpenSubtitles).
    static let all: [SubtitleLanguage] = [
        "pt-br", "pt-pt", "en", "es", "fr", "de", "it", "nl", "pl", "ru", "uk", "cs", "sk", "hu", "ro", "bg",
        "hr", "sr", "sl", "el", "tr", "ar", "he", "fa", "hi", "id", "ms", "vi", "th", "ja", "ko", "zh-cn",
        "zh-tw", "sv", "no", "da", "fi", "et", "lv", "lt", "ca", "eu", "gl",
    ].map(SubtitleLanguage.init)

    /// Ordenados pelo nome para mostrar em listas.
    static var sortedByName: [SubtitleLanguage] {
        all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
