import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UITabBarDelegate {

    private var tabChannel: FlutterMethodChannel?
    private var badgeChannel: FlutterMethodChannel?
    private var uploadTaskChannel: FlutterMethodChannel?
    private var backgroundUploadChannel: FlutterMethodChannel?
    private var nativeTabBar: UITabBar?
    // Held so we can replay the launch notification into firebase_messaging after
    // it registers late — see replayLaunchNotificationForFirebaseMessaging(_:).
    private var pendingLaunchOptions: [UIApplication.LaunchOptionsKey: Any]?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        pendingLaunchOptions = launchOptions

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
        replayLaunchNotificationForFirebaseMessaging(engineBridge.pluginRegistry)
        registerBadgeChannel(with: engineBridge.pluginRegistry)
        registerNativeCityMap(with: engineBridge.pluginRegistry)
        MapSnapshot.register(with: engineBridge.pluginRegistry)
        registerShareChannel(with: engineBridge.pluginRegistry)
        registerUploadTaskChannel(with: engineBridge.pluginRegistry)
        registerBackgroundUploadChannel(with: engineBridge.pluginRegistry)
        // Reconnects to transfers still running from a previous launch.
        BackgroundUploader.shared.start()

        if #available(iOS 26, *) {
            setupNativeTabBar(with: engineBridge.pluginRegistry)
        }
    }

    /// firebase_messaging installs all of its notification handling — the
    /// UNUserNotificationCenter delegate, app-delegate swizzling, and the
    /// cold-start "initial notification" capture — from a
    /// UIApplicationDidFinishLaunchingNotification observer it adds when its
    /// plugin registers. Because our plugins register late (implicit engine),
    /// that system notification already fired and was missed, so none of that
    /// setup ran: on iOS a tapped notification just foregrounded the app and
    /// onMessageOpenedApp / getInitialMessage never fired (nothing routed).
    /// Android has no such step, which is why it worked there.
    ///
    /// Invoke that same handler directly now, passing the real launch options so
    /// a cold-start tap is still captured. Targeting just this plugin (rather
    /// than re-broadcasting the system notification) avoids disturbing other
    /// launch observers.
    private func replayLaunchNotificationForFirebaseMessaging(_ registry: FlutterPluginRegistry) {
        guard let messaging = registry.valuePublished(byPlugin: "FLTFirebaseMessagingPlugin") else { return }
        let selector = NSSelectorFromString("application_onDidFinishLaunchingNotification:")
        guard messaging.responds(to: selector) else { return }

        var userInfo: [AnyHashable: Any]? = nil
        if let remote = pendingLaunchOptions?[.remoteNotification] {
            userInfo = [UIApplication.LaunchOptionsKey.remoteNotification.rawValue: remote]
        }
        let note = NSNotification(
            name: UIApplication.didFinishLaunchingNotification,
            object: nil,
            userInfo: userInfo
        )
        messaging.perform(selector, with: note)
    }

    // MARK: - App icon badge

    /// Lets Flutter put the red count on the home-screen icon back down.
    ///
    /// Pushes carry `aps.badge` and so can raise it (see push/senders.py on the
    /// backend), but nothing lowers it when the user actually reads a message
    /// or opens the notifications bell — iOS keeps whatever the last push said
    /// until the app itself writes a new value. This is that write.
    ///
    /// iOS only. Android launchers derive their own badge from the
    /// notifications sitting in the tray, so there is nothing to set there and
    /// the Dart side simply finds no channel.
    private func registerBadgeChannel(with registry: FlutterPluginRegistry) {
        guard let r = registry.registrar(forPlugin: "NeatBadge") else { return }
        let channel = FlutterMethodChannel(name: "com.neat/badge",
                                           binaryMessenger: r.messenger())
        channel.setMethodCallHandler { call, result in
            guard call.method == "setBadge", let count = call.arguments as? Int else {
                result(FlutterMethodNotImplemented)
                return
            }
            DispatchQueue.main.async {
                if #available(iOS 16.0, *) {
                    // setBadgeCount is the supported route from iOS 16 on;
                    // applicationIconBadgeNumber is deprecated in iOS 17.
                    UNUserNotificationCenter.current().setBadgeCount(count)
                } else {
                    UIApplication.shared.applicationIconBadgeNumber = count
                }
                result(nil)
            }
        }
        badgeChannel = channel
    }

    // MARK: - Uploads that outlive the app

    private func registerBackgroundUploadChannel(with registry: FlutterPluginRegistry) {
        guard let r = registry.registrar(forPlugin: "NeatBackgroundUpload") else { return }
        let channel = FlutterMethodChannel(name: "com.neat/bgupload",
                                           binaryMessenger: r.messenger())
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "enqueue":
                guard
                    let a = call.arguments as? [String: Any],
                    let name = a["name"] as? String,
                    let urlString = a["url"] as? String,
                    let url = URL(string: urlString),
                    let path = a["filePath"] as? String
                else {
                    result(false)
                    return
                }
                BackgroundUploader.shared.enqueue(
                    name: name,
                    url: url,
                    headers: a["headers"] as? [String: String] ?? [:],
                    fileURL: URL(fileURLWithPath: path),
                    fieldName: a["field"] as? String ?? "file",
                    fileName: a["fileName"] as? String ?? "upload.bin",
                    fields: a["fields"] as? [String: String] ?? [:]
                ) { ok, reason in
                    DispatchQueue.main.async {
                        result(ok ? "ok" : reason)
                    }
                }
            case "drain":
                result(BackgroundUploader.shared.drainResults())
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        backgroundUploadChannel = channel
        BackgroundUploader.shared.channel = channel
    }

    /// iOS relaunches the app when a background transfer finishes with nobody
    /// listening. Holding the handler until the session says it has delivered
    /// everything is what stops the app being suspended again mid-report.
    override func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundUploader.shared.backgroundCompletion = completionHandler
        BackgroundUploader.shared.start()
    }

    // MARK: - Keeping an upload alive in the background

    /// Background task assertions held while a post is uploading.
    ///
    /// Leaving the app suspends the process, and a suspended process has its
    /// sockets torn down — which is why walking away mid-post lost the upload.
    /// An assertion asks iOS to keep the app running a little longer after it
    /// leaves the screen; the system grants around thirty seconds, which at
    /// this app's measured upload speed covers a typical compressed video.
    ///
    /// Deliberately not a promise of unlimited time: a very large upload can
    /// still be cut short when the assertion expires, and the only real cure
    /// for that is a background URLSession, which continues out of process.
    private var uploadTasks: [String: UIBackgroundTaskIdentifier] = [:]

    private func registerUploadTaskChannel(with registry: FlutterPluginRegistry) {
        guard let r = registry.registrar(forPlugin: "NeatUploadTask") else { return }
        let channel = FlutterMethodChannel(name: "com.neat/uploadtask",
                                           binaryMessenger: r.messenger())
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self, let name = call.arguments as? String else {
                result(FlutterMethodNotImplemented)
                return
            }
            DispatchQueue.main.async {
                switch call.method {
                case "begin":
                    // Replacing an assertion under the same name would leak the
                    // previous one, and iOS kills an app that leaks them.
                    self.endUploadTask(name)
                    let id = UIApplication.shared.beginBackgroundTask(withName: name) {
                        // Time is up. Ending it here is required — the system
                        // terminates an app that lets one expire unattended.
                        self.endUploadTask(name)
                    }
                    if id != .invalid { self.uploadTasks[name] = id }
                    result(id != .invalid)
                case "end":
                    self.endUploadTask(name)
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }
        uploadTaskChannel = channel
    }

    private func endUploadTask(_ name: String) {
        guard let id = uploadTasks.removeValue(forKey: name) else { return }
        UIApplication.shared.endBackgroundTask(id)
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
            case "isNativeTabBarReady":
                // Flutter pulls this on startup instead of relying solely on
                // the nativeTabBarReady push below. The push fires once, at
                // engine init — long before HomePage exists on a fresh
                // sign-up, so a listener that registers later would never
                // hear it and the app would fall back to Flutter's own bar
                // until the next launch.
                DispatchQueue.main.async {
                    result(self?.nativeTabBar != nil)
                }
            case "setProfileImage":
                let args = call.arguments as? [String: Any]
                if let typedData = args?["bytes"] as? FlutterStandardTypedData {
                    DispatchQueue.main.async {
                        self?.setProfileTabImage(from: typedData.data)
                    }
                } else if let urlString = args?["url"] as? String, let url = URL(string: urlString) {
                    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                        guard let data else { return }
                        DispatchQueue.main.async {
                            self?.setProfileTabImage(from: data)
                        }
                    }.resume()
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

            // Match the app's dark/light background colors.
            let darkBg  = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
            let lightBg = UIColor.white
            let bg = UIColor { $0.userInterfaceStyle == .dark ? darkBg : lightBg }
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = bg
            bar.standardAppearance    = appearance
            bar.scrollEdgeAppearance  = appearance

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

    @available(iOS 26, *)
    private func setProfileTabImage(from data: Data) {
        guard let image = UIImage(data: data) else { return }
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        let clipped = renderer.image { ctx in
            ctx.cgContext.addEllipse(in: CGRect(origin: .zero, size: size))
            ctx.cgContext.clip()
            image.draw(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysOriginal)
        nativeTabBar?.items?[4].image = clipped
        nativeTabBar?.items?[4].selectedImage = clipped
    }

    // MARK: - UITabBarDelegate

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        tabChannel?.invokeMethod("onTabTapped", arguments: item.tag)
    }
}
