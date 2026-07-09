import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UITabBarDelegate {

    private var tabChannel: FlutterMethodChannel?
    private var nativeTabBar: UITabBar?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // firebase_messaging normally does this itself, by observing
        // UIApplicationDidFinishLaunchingNotification when its plugin is
        // registered — but GeneratedPluginRegistrant.register(with:) here
        // only runs later, in didInitializeImplicitFlutterEngine(_:), by
        // which point that one-shot notification has already fired and been
        // missed. Without this, the app never asks Apple for an APNs device
        // token at all (confirmed via device syslog: no apsd connection).
        application.registerForRemoteNotifications()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Called by Flutter when the implicit engine is fully initialised —
    // the binary messenger is ready and the view hierarchy is set up.
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        registerNativeCityMap(with: engineBridge.pluginRegistry)
        registerShareChannel(with: engineBridge.pluginRegistry)

        if #available(iOS 26, *) {
            setupNativeTabBar(with: engineBridge.pluginRegistry)
        }
    }

    // MARK: - Native share sheet

    private func registerShareChannel(with registry: FlutterPluginRegistry) {
        guard let r = registry.registrar(forPlugin: "NeatShare") else { return }
        let channel = FlutterMethodChannel(name: "com.neat/share",
                                           binaryMessenger: r.messenger())
        channel.setMethodCallHandler { [weak self] call, result in
            let args = call.arguments as? [String: Any]
            let text = args?["text"] as? String ?? ""

            switch call.method {
            case "share":
                let imageTypedData = args?["imageBytes"] as? FlutterStandardTypedData
                let imageData = imageTypedData?.data
                DispatchQueue.main.async {
                    self?.presentNativeShareSheet(text: text, imageData: imageData, result: result)
                }
            case "shareToInstagramDm":
                DispatchQueue.main.async {
                    self?.shareToInstagramDm(text: text, result: result)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func presentNativeShareSheet(text: String, imageData: Data?, result: @escaping FlutterResult) {
        var items: [Any] = []
        if let data = imageData, let image = UIImage(data: data) {
            items.append(image)
        }
        if !text.isEmpty { items.append(text) }
        guard !items.isEmpty else { result(nil); return }

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in result(nil) }

        // Walk to the topmost presented view controller so we always have
        // a valid presenter regardless of what Flutter modals are showing.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var presenter = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let next = presenter?.presentedViewController { presenter = next }

        // iPad/Mac popover anchor — centre of the screen
        if let pop = vc.popoverPresentationController, let view = presenter?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }

        presenter?.present(vc, animated: true)
    }

    private func shareToInstagramDm(text: String, result: @escaping FlutterResult) {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        guard let url = URL(string: "instagram://sharesheet?text=\(encoded)"),
              UIApplication.shared.canOpenURL(url) else {
            // Instagram not installed — fall back to the system share sheet
            presentNativeShareSheet(text: text, imageData: nil, result: result)
            return
        }
        UIApplication.shared.open(url, options: [:]) { _ in result(nil) }
    }

    // MARK: - NativeCityMap plugin

    private func registerNativeCityMap(with registrar: FlutterPluginRegistry) {
        guard let r = registrar.registrar(forPlugin: "NativeCityMap") else { return }
        let factory = NativeCityMapFactory(messenger: r.messenger())
        r.register(factory, withId: "neat/native_city_map")
    }

    // MARK: - iOS 26 native tab bar

    @available(iOS 26, *)
    private func setupNativeTabBar(with registry: FlutterPluginRegistry) {
        guard let registrar = registry.registrar(forPlugin: "NeatNativeTabBar") else { return }
        let channel = FlutterMethodChannel(name: "com.neat/tabbar",
                                           binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "syncTab":
                guard let index = call.arguments as? Int else {
                    result(FlutterMethodNotImplemented)
                    return
                }
                DispatchQueue.main.async {
                    self?.nativeTabBar?.selectedItem = self?.nativeTabBar?.items?[index]
                }
                result(nil)
            case "hideTabBar":
                DispatchQueue.main.async {
                    self?.nativeTabBar?.isHidden = true
                }
                result(nil)
            case "showTabBar":
                DispatchQueue.main.async {
                    self?.nativeTabBar?.isHidden = false
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        tabChannel = channel

        // All UIKit work must happen on the main thread.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Locate the Flutter root view from the active window scene.
            let rootView = UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .windows
                .first?
                .rootViewController?
                .view
            guard let rootView else { return }

            let bar = UITabBar()
            bar.delegate = self
            bar.items = [
                self.makeItem("house",              "house.fill",              0),
                self.makeItem("magnifyingglass",    "magnifyingglass",         1),
                self.makeItem("plus.circle",        "plus.circle.fill",        2),
                self.makeItem("map",                "map.fill",                3),
                self.makeItem("person.crop.circle", "person.crop.circle.fill", 4),
            ]
            bar.selectedItem = bar.items?.first
            bar.tintColor = .label
            bar.unselectedItemTintColor = .secondaryLabel
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.isHidden = true

            rootView.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            ])
            self.nativeTabBar = bar

            // Tell Flutter the native bar is live so it can hide its own.
            self.tabChannel?.invokeMethod("nativeTabBarReady", arguments: nil)
        }
    }

    private func makeItem(_ outlined: String, _ filled: String, _ tag: Int) -> UITabBarItem {
        let item = UITabBarItem(title: nil, image: UIImage(systemName: outlined), tag: tag)
        item.selectedImage = UIImage(systemName: filled)
        return item
    }

    // MARK: - UITabBarDelegate

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        tabChannel?.invokeMethod("onTabTapped", arguments: item.tag)
    }
}
