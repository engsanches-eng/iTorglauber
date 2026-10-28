import Foundation

/// Categoria de torrent (espelha `Category` do app Android).
enum Category: String, CaseIterable, Codable, Hashable, Identifiable {
    case all = "All"
    case anime = "Anime"
    case apps = "Apps"
    case books = "Books"
    case games = "Games"
    case movies = "Movies"
    case music = "Music"
    case porn = "Porn"
    case series = "Series"
    case other = "Other"

    var id: String { rawValue }
    var isNSFW: Bool { self == .porn }

    var title: String {
        switch self {
        case .all: return L("Todas")
        case .anime: return L("Anime")
        case .apps: return L("Apps")
        case .books: return L("Livros")
        case .games: return L("Jogos")
        case .movies: return L("Filmes")
        case .music: return L("Música")
        case .porn: return L("Adulto")
        case .series: return L("Séries")
        case .other: return L("Outros")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .anime: return "sparkles.tv"
        case .apps: return "app.badge"
        case .books: return "book"
        case .games: return "gamecontroller"
        case .movies: return "film"
        case .music: return "music.note"
        case .porn: return "exclamationmark.triangle"
        case .series: return "tv"
        case .other: return "ellipsis.circle"
        }
    }
}

/// Estado do link magnet de um torrent.
enum MagnetUri: Codable, Hashable {
    /// Link magnet já disponível.
    case available(String)
    /// Precisa buscar o link em outra página (via `MagnetUriProvider`).
    case requiresFetch(String)
}

/// Metadados de um torrent retornado por um buscador.
struct Torrent: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    var size: String? = nil
    var seeders: Int? = nil
    var peers: Int? = nil
    let providerName: String
    var uploadDate: Date? = nil
    var category: Category? = nil
    var detailsPageUrl: String? = nil
    var magnetUri: MagnetUri
    var fileDownloadLink: String? = nil

    var isNSFW: Bool { category?.isNSFW ?? false }
    var isDead: Bool { seeders == 0 && peers == 0 }
    var sizeBytes: Double { size.map(FileSizeUtils.getBytes) ?? 0 }
}

/// Proteção Cloudflare do buscador.
enum CloudflareProtectionStatus: Codable {
    case unprotected, locked, unlocked
}

enum ProviderSafety: Hashable {
    case safe
    case unsafe(reason: String)
    var isUnsafe: Bool { if case .unsafe = self { return true }; return false }
}

enum ProviderOrigin: String, Codable { case builtin, torznab }

/// Critério de ordenação dos resultados.
enum SortCriteria: String, CaseIterable, Codable, Identifiable {
    case name = "Name", seeders = "Seeders", peers = "Peers", fileSize = "FileSize", date = "Date"
    var id: String { rawValue }
    static let `default`: SortCriteria = .seeders
    var title: String {
        switch self {
        case .name: return L("Nome")
        case .seeders: return L("Seeders")
        case .peers: return L("Peers")
        case .fileSize: return L("Tamanho")
        case .date: return L("Data")
        }
    }
}

enum SortOrder: String, CaseIterable, Codable, Identifiable {
    case ascending = "Ascending", descending = "Descending"
    var id: String { rawValue }
    static let `default`: SortOrder = .descending
    var title: String { self == .ascending ? L("Crescente") : L("Decrescente") }
}

struct SortOptions: Codable, Hashable {
    var criteria: SortCriteria = .default
    var order: SortOrder = .default
}

/// Erro de um buscador durante a pesquisa.
struct SearchProviderError: Identifiable, Hashable {
    enum Kind: Hashable { case crash, cloudflareChallenge }
    var id: String { providerId }
    let providerId: String
    let providerName: String
    let providerUrl: String
    let kind: Kind
    let message: String
    var isRetryable: Bool { kind == .crash }
}

/// Configuração de um indexador Torznab (Jackett/Prowlarr) adicionado pelo usuário.
struct TorznabConfig: Codable, Identifiable, Hashable {
    var id: String
    var searchProviderName: String
    var url: String
    var apiKey: String
    var supportedCategories: Set<Category>
}

/// Registro do histórico de buscas.
struct SearchHistoryItem: Codable, Identifiable, Hashable {
    var id: String { query }
    let query: String
    var date: Date
}

/// Favorito salvo pelo usuário.
struct Bookmark: Codable, Identifiable, Hashable {
    var id: String { torrent.id }
    var torrent: Torrent
    var addedAt: Date
}

/// Tradução: as chaves são o texto em português; o catálogo traz o inglês.
@inline(__always)
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: .module, comment: ""), arguments: args)
}
