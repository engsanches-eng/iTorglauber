import Foundation

/// Lista dos buscadores embutidos (mesma ordem do BuiltinSearchProvidersModule.kt).
enum ProviderRegistry {
    static let builtin: [SearchProvider] = [
        AniLibria(), AniRena(), AnimeTosho(), AudioBookBay(), BTDigg(), BangumiMoe(),
        BitSearch(), BlueRoms(), Bt4g(), Btsow(), Dmhy(), EpubLibre(),
        Ext(), Eztv(), FileMood(), FitGirlRepacks(), InternetArchive(), Knaben(),
        LimeTorrents(), LinuxTracker(), MegaPeer(), Mikan(), MyPornClub(), NekoBT(),
        NoNameClub(), Nyaa(), OxTorrent(), Rutor(), SubsPlease(), Sukebei(),
        ThePirateBay(), TheRarBg(), ThirteenThirtySevenX(), TokyoToshokan(), Torrent9(), TorrentDatabase(),
        TorrentDownload(), TorrentDownloads(), TorrentKitty(), TorrentsCSV(), Torrentz(), UIndex(),
        XXXClub(), XXXTracker(), Yts(), ZeroMagnet(),
    ]
}
