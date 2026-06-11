import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerNativeCityMap(with: engineBridge.pluginRegistry)
  }

  private func registerNativeCityMap(with registrar: FlutterPluginRegistry) {
    guard let pluginRegistrar = registrar.registrar(forPlugin: "NativeCityMap") else { return }
    let factory = NativeCityMapFactory(messenger: pluginRegistrar.messenger())
    pluginRegistrar.register(factory, withId: "neat/native_city_map")
  }
}
