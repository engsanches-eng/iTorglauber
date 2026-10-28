import Foundation
import SwiftUI

/// Ajustes da aba Legenda. Ficam só no aparelho; senha, token e chave da API vão para o Keychain.
@MainActor
final class LegendaSettings: ObservableObject {
    static let shared = LegendaSettings()

    enum TapAction: String, CaseIterable, Identifiable {
        case menu, best
        var id: String { rawValue }
        var title: String { self == .menu ? L("Mostrar menu") : L("Baixar a melhor direto") }
    }

    enum Naming: String, CaseIterable, Identifiable {
        case plain, withLanguage
        var id: String { rawValue }
        var title: String { self == .plain ? L("Filme.srt") : L("Filme.pt-BR.srt") }
    }

    enum Conflict: String, CaseIterable, Identifiable {
        case ask, replace, keepBoth
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ask: return L("Perguntar")
            case .replace: return L("Substituir")
            case .keepBoth: return L("Manter as duas")
            }
        }
    }

    private let d = UserDefaults(suiteName: "com.glauber.superapp.legenda") ?? .standard

    @Published var primary: SubtitleLanguage { didSet { d.set(primary.code, forKey: "primary") } }
    /// nil = nenhum
    @Published var secondary: SubtitleLanguage? { didSet { d.set(secondary?.code ?? "", forKey: "secondary") } }
    @Published var tapAction: TapAction { didSet { d.set(tapAction.rawValue, forKey: "tap_action") } }
    @Published var naming: Naming { didSet { d.set(naming.rawValue, forKey: "naming") } }
    @Published var conflict: Conflict { didSet { d.set(conflict.rawValue, forKey: "conflict") } }
    @Published var includeHearingImpaired: Bool { didSet { d.set(includeHearingImpaired, forKey: "hearing_impaired") } }
    @Published var includeMachineTranslated: Bool { didSet { d.set(includeMachineTranslated, forKey: "machine_translated") } }
    @Published var onlyVideos: Bool { didSet { d.set(onlyVideos, forKey: "only_videos") } }

    // Conta OpenSubtitles
    @Published var apiKey: String { didSet { LegendaKeychain.set(apiKey.trimmed, for: "api_key") } }
    @Published var username: String { didSet { d.set(username, forKey: "username") } }
    @Published var loggedInUser: String? { didSet { d.set(loggedInUser, forKey: "logged_user") } }
    /// Downloads restantes informados pelo servidor e quando foi a última informação.
    @Published var remainingDownloads: Int? { didSet { d.set(remainingDownloads ?? -1, forKey: "remaining") } }
    @Published var remainingUpdatedAt: Date? { didSet { d.set(remainingUpdatedAt, forKey: "remaining_at") } }

    /// Pastas que o usuário adicionou (bookmark para continuar com acesso depois de fechar o app).
    @Published var savedFolders: [SavedFolder] { didSet { persistFolders() } }

    private init() {
        primary = SubtitleLanguage(d.string(forKey: "primary") ?? SubtitleLanguage.portugueseBR.code)
        let sec = d.object(forKey: "secondary") == nil ? SubtitleLanguage.english.code : (d.string(forKey: "secondary") ?? "")
        secondary = sec.isEmpty ? nil : SubtitleLanguage(sec)
        tapAction = TapAction(rawValue: d.string(forKey: "tap_action") ?? "") ?? .menu
        naming = Naming(rawValue: d.string(forKey: "naming") ?? "") ?? .plain
        conflict = Conflict(rawValue: d.string(forKey: "conflict") ?? "") ?? .ask
        includeHearingImpaired = d.object(forKey: "hearing_impaired") as? Bool ?? true
        includeMachineTranslated = d.object(forKey: "machine_translated") as? Bool ?? false
        onlyVideos = d.object(forKey: "only_videos") as? Bool ?? true
        apiKey = LegendaKeychain.get("api_key") ?? ""
        username = d.string(forKey: "username") ?? ""
        loggedInUser = d.string(forKey: "logged_user")
        let r = d.object(forKey: "remaining") as? Int ?? -1
        remainingDownloads = r < 0 ? nil : r
        remainingUpdatedAt = d.object(forKey: "remaining_at") as? Date
        if let data = d.data(forKey: "folders"), let f = try? JSONDecoder().decode([SavedFolder].self, from: data) {
            savedFolders = f
        } else {
            savedFolders = []
        }
    }

    /// Idiomas da busca padrão: primário e, se houver, secundário.
    var searchLanguages: [SubtitleLanguage] {
        var l = [primary]
        if let s = secondary, s != primary { l.append(s) }
        return l
    }

    var hasApiKey: Bool { !apiKey.trimmed.isEmpty }

    var password: String {
        get { LegendaKeychain.get("password") ?? "" }
        set { LegendaKeychain.set(newValue, for: "password") }
    }

    var token: String? {
        get { LegendaKeychain.get("token") }
        set { LegendaKeychain.set(newValue, for: "token") }
    }

    var apiBaseHost: String {
        get { d.string(forKey: "base_host") ?? "api.opensubtitles.com" }
        set { d.set(newValue, forKey: "base_host") }
    }

    func logout() {
        token = nil
        password = ""
        loggedInUser = nil
        apiBaseHost = "api.opensubtitles.com"
    }

    // MARK: Pastas

    func addFolder(_ url: URL) throws {
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        // Mesma pasta de novo: só atualiza o acesso.
        if let i = savedFolders.firstIndex(where: { $0.path == url.path }) {
            savedFolders[i].bookmark = data
        } else {
            savedFolders.append(SavedFolder(id: UUID(), name: name, path: url.path, bookmark: data))
        }
    }

    func removeFolder(_ f: SavedFolder) { savedFolders.removeAll { $0.id == f.id } }

    /// Converte o bookmark em URL; renova o bookmark se o iOS avisar que ficou antigo.
    func resolve(_ f: SavedFolder) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: f.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
               let i = savedFolders.firstIndex(where: { $0.id == f.id }) {
                savedFolders[i].bookmark = fresh
            }
        }
        return url
    }

    private func persistFolders() {
        d.set(try? JSONEncoder().encode(savedFolders), forKey: "folders")
    }
}

struct SavedFolder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var bookmark: Data
}
