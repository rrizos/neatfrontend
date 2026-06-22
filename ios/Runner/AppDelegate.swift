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
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Called by Flutter when the implicit engine is fully initialised —
    // the binary messenger is ready and the view hierarchy is set up.
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        registerNativeCityMap(with: engineBridge.pluginRegistry)

        if #available(iOS 26, *) {
            setupNativeTabBar(with: engineBridge.pluginRegistry)
        }
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
