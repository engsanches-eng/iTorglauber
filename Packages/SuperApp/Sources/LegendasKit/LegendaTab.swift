import SwiftUI
import UIKit

/// Ponto de entrada da aba "Legenda" no superapp.
public enum LegendaTab {
    public static var title: String { L("Legenda") }

    /// Tela raiz da aba, pronta para pôr numa UITabBarController.
    /// `locations` são pastas fixas oferecidas pelo app (ex.: os downloads do iTorrent).
    @MainActor public static func makeViewController(locations: [LegendaLocation]) -> UIViewController {
        let vc = UIHostingController(rootView: LegendaRootView(builtIn: locations))
        vc.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: "captions.bubble"), tag: 2)
        return vc
    }
}

extension LegendaTab {
    /// Nome do local com os downloads do iTorrent.
    public static var iTorrentDownloadsName: String { L("Downloads do iTorrent") }
}
