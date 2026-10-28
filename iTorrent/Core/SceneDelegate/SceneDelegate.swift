//
//  SceneDelegate.swift
//  iTorrent
//
//  Created by Daniil Vinogradov on 29/10/2023.
//

import LibTorrent
import MvvmFoundation
import UIKit
import AVKit
import TorrentSearchKit
import LegendasKit

class SceneDelegate: MvvmSceneDelegate {
    override func initialSetup() {
        UIView.enableUIColorsToLayer()
    }

    override func register(in container: Container) {
        registerAVPlayer(in: container)
        container.register(type: UINavigationController.self, factory: BaseNavigationController.init)
        container.register(type: UISplitViewController.self, factory: BaseSplitViewController.init)
        container.registerSingleton(factory: { TorrentService.shared })
        container.registerSingleton(factory: { PreferencesStorage.shared })
        container.registerSingleton(factory: { BackgroundService.shared })
        container.registerSingleton(factory: NetworkMonitoringService.init)
        container.registerSingleton(factory: ImageLoader.init)
        container.registerSingleton(factory: TrackersListService.init)
        container.registerDaemon(factory: PatreonService.init)
        container.registerDaemon(factory: TorrentMonitoringService.init)
        container.registerDaemon(factory: RssFeedProvider.init)
        container.registerDaemon(factory: WebServerService.init)
        container.registerDaemon(factory: LiveActivityService.init)
        container.registerDaemon(factory: IntentsService.init)
        container.registerDaemon(factory: AdsManager.init)
        container.registerDaemon(factory: CellularNotAllowedOverlay.init)
    }

    override func routing(in router: Router) {
        // MARK: Cells
        router.register(TorrentListItemView.self)
        router.register(TorrentDetailProgressCellView.self)

        router.register(RssFeedCell.self)
        router.register(RssChannelItemCell.self)

        router.register(TrackerCellView.self)

        router.register(DetailCellView.self)
        router.register(ToggleCellView.self)

        router.register(PRSwitchView.self)
        router.register(PRButtonView.self)
        router.register(PRStorageCell.self)
        router.register(PRColorPickerCell.self)
        router.register(MenuButtonCellView.self)

        // MARK: Controllers
        router.register(BaseHostingViewController<StoragePreferencesView>.self)

        router.register(TorrentListViewController<TorrentListViewModel>.self)
        router.register(TorrentDetailsViewController<TorrentDetailsViewModel>.self)
        router.register(TorrentFilesViewController<TorrentFilesViewModel>.self)
        router.register(TorrentAddViewController<TorrentAddViewModel>.self)
        router.register(TorrentTrackersViewController<TorrentTrackersViewModel>.self)

        router.register(CellularToggleSetupViewController<CellularToggleSetupViewModel>.self)

        router.register(BasePreferencesViewController<PreferencesViewModel>.self)
        router.register(BasePreferencesViewController<ProxyPreferencesViewModel>.self)
        router.register(TrackersListPreferencesViewController.self)
        router.register(TrackersListDetailsPreferencesViewController.self)
        router.register(BasePreferencesViewController<ConnectionPreferencesViewModel>.self)
        router.register(BasePreferencesViewController<FileSharingPreferencesViewModel>.self)
        router.register(PreferencesSectionGroupingViewController.self)
        router.register(PatreonPreferencesViewController.self)

        router.register(RssListViewController.self)
        router.register(RssChannelViewController.self)
        router.register(RssDetailsViewController.self)
        router.register(RssListPreferencesViewController.self)
        router.register(RssSearchViewController.self)

        router.register(VLCPlayerViewController.self)
    }

    override func resolveRootVC(with router: Router) -> UIViewController {
        let vc = router.resolve(TorrentListViewModel())

        let nvc = UINavigationController.resolve()
        nvc.viewControllers = [vc]

        let svc = UISplitViewController.resolve()
        svc.viewControllers = [nvc]

        return makeSuperAppTabs(iTorrent: svc)
    }

    override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        invokeInitialSetup()
        connectionOptions.urlContexts.forEach { context in
            let url = context.url
            processURL(url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.forEach { context in
            let url = context.url
            processURL(url)
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        UIApplication.shared.applicationIconBadgeNumber = 0
        startBackgroundIfNeeded()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        UIApplication.shared.applicationIconBadgeNumber = 0
        stopBackground()
    }

    override func binding() {
        disposeBag.bind {
            tintColorBind
            appAppearanceBind
            backgroundDownloadModeBind
            backgroundStateObserverBind
        }
    }
}

private extension SceneDelegate {
    func invokeInitialSetup() {
        guard let window else { return }

        Task { @MainActor [weak window] in
            try await Task.sleep(for: .seconds(0.5))
            guard let window else { return }
            await InitialSetupFlow.startIfNeeded(in: window)
        }
    }
}

// MARK: - Superapp: Buscar · iTorrent · Legenda

extension SceneDelegate {
    private static let lastTabKey = "superapp_last_tab"

    func makeSuperAppTabs(iTorrent svc: UIViewController) -> UIViewController {
        svc.tabBarItem = UITabBarItem(title: "iTorrent", image: UIImage(systemName: "arrow.down.circle"), tag: 1)

        // Links magnet da aba Buscar entram direto no iTorrent, sem sair do app.
        BuscaTab.openMagnet = { [weak self] url in
            self?.addMagnetFromSearch(url) ?? false
        }

        let downloads = LegendaLocation(name: LegendaTab.iTorrentDownloadsName,
                                        url: TorrentService.downloadPath,
                                        systemImage: "arrow.down.circle")

        let tabs = SuperAppTabBarController()
        tabs.viewControllers = [
            BuscaTab.makeViewController(),
            svc,
            LegendaTab.makeViewController(locations: [downloads]),
        ]
        let last = UserDefaults.standard.object(forKey: Self.lastTabKey) as? Int ?? 1
        tabs.selectedIndex = (0..<3).contains(last) ? last : 1
        tabs.onSelect = { index in UserDefaults.standard.set(index, forKey: Self.lastTabKey) }
        return tabs
    }

    /// Adiciona o magnet no iTorrent e mostra a aba de downloads.
    func addMagnetFromSearch(_ url: URL) -> Bool {
        guard url.absoluteString.lowercased().hasPrefix("magnet:"),
              let magnet = MagnetURI(with: url)
        else { return false }

        TorrentService.shared.addTorrent(by: magnet)
        if let tabs = window?.rootViewController as? UITabBarController,
           let index = tabs.viewControllers?.firstIndex(where: { $0 is UISplitViewController }) {
            tabs.selectedIndex = index
            UserDefaults.standard.set(index, forKey: Self.lastTabKey)
        }
        return true
    }
}

/// Barra de abas do superapp (avisa qual aba foi escolhida para reabrir nela).
final class SuperAppTabBarController: UITabBarController, UITabBarControllerDelegate {
    var onSelect: ((Int) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        onSelect?(selectedIndex)
    }
}

extension UIViewController {
    /// A tela do iTorrent (split view). No superapp ela fica dentro da barra de abas.
    var iTorrentSplit: UISplitViewController? {
        if let svc = self as? UISplitViewController { return svc }
        if let tabs = self as? UITabBarController {
            return tabs.viewControllers?.lazy.compactMap { $0 as? UISplitViewController }.first
        }
        return nil
    }
}
