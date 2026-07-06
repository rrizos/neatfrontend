import Flutter
import MapKit
import UIKit

// MARK: - Factory

final class NativeCityMapFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> any FlutterPlatformView {
    NativeCityMapView(frame: frame, args: args, messenger: messenger)
  }
}

// MARK: - Platform View

final class NativeCityMapView: NSObject, FlutterPlatformView, MKMapViewDelegate {
  private let map = MKMapView()
  private var channel: FlutterMethodChannel?

  private let overview = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 39.0, longitude: 22.9),
    span: MKCoordinateSpan(latitudeDelta: 7.5, longitudeDelta: 7.5)
  )

  init(frame: CGRect, args: Any?, messenger: FlutterBinaryMessenger) {
    super.init()
    let isDark = (args as? [String: Any])?["isDark"] as? Bool ?? true
    configureMap(frame: frame, isDark: isDark)
    wireChannel(messenger: messenger)
    loadCities(from: args)
  }

  func view() -> UIView { map }

  // MARK: MKMapViewDelegate

  func mapView(_ mv: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    guard annotation is MKPointAnnotation else { return nil }
    let v = mv.dequeueReusableAnnotationView(
      withIdentifier: "pin", for: annotation
    ) as! MKMarkerAnnotationView
    v.markerTintColor = .systemGreen
    v.glyphImage = UIImage(systemName: "mappin")
    v.canShowCallout = false
    return v
  }

  func mapView(_ mv: MKMapView, didSelect view: MKAnnotationView) {
    guard
      let annotation = view.annotation,
      let name = annotation.title ?? nil,
      !name.isEmpty
    else { return }

    // Lock the map immediately so no further taps can land while the
    // Flutter card is visible. Unlocked as the first act of zoomOut().
    mv.isUserInteractionEnabled = false

    mv.setRegion(
      MKCoordinateRegion(
        center: annotation.coordinate,
        latitudinalMeters: 70_000,
        longitudinalMeters: 70_000
      ),
      animated: true
    )
    channel?.invokeMethod("citySelected", arguments: name)
  }

  // MARK: Private

  private func zoomOut() {
    // Unlock first — this must happen unconditionally so the map is never
    // permanently stuck even if something else in this function throws.
    map.isUserInteractionEnabled = true
    map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: false) }
    map.setRegion(overview, animated: true)
  }

  private func configureMap(frame: CGRect, isDark: Bool) {
    map.frame = frame
    map.delegate = self
    map.isRotateEnabled = false
    map.isPitchEnabled = false
    map.showsCompass = false
    map.showsScale = false
    map.showsTraffic = false
    map.pointOfInterestFilter = .excludingAll
    map.overrideUserInterfaceStyle = isDark ? .dark : .light
    map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")
    map.setRegion(overview, animated: false)

    // Constrain centre to a padded Greece bounding box so panning can't
    // reach a different country, but there's breathing room around every pin.
    if #available(iOS 13.0, *) {
      map.setCameraBoundary(
        MKMapView.CameraBoundary(coordinateRegion: MKCoordinateRegion(
          center: CLLocationCoordinate2D(latitude: 38.0, longitude: 24.0),
          span: MKCoordinateSpan(latitudeDelta: 12.0, longitudeDelta: 16.0)
        )),
        animated: false
      )
      // Cap zoom-out so the user can't pull back to see the whole planet.
      map.setCameraZoomRange(
        MKMapView.CameraZoomRange(maxCenterCoordinateDistance: 2_500_000),
        animated: false
      )
    }
  }

  private func wireChannel(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "neat/native_city_map_channel",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "zoomOut" { self?.zoomOut() }
      if call.method == "updateColorScheme", let isDark = call.arguments as? Bool {
        self?.map.overrideUserInterfaceStyle = isDark ? .dark : .light
      }
      result(nil)
    }
  }

  private func loadCities(from args: Any?) {
    guard
      let dict   = args as? [String: Any],
      let cities = dict["cities"] as? [[String: Any]]
    else { return }

    let annotations: [MKPointAnnotation] = cities.compactMap { c in
      guard
        let name = c["name"]      as? String,
        let lat  = c["latitude"]  as? Double,
        let lng  = c["longitude"] as? Double
      else { return nil }
      let a = MKPointAnnotation()
      a.title = name
      a.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
      return a
    }
    map.addAnnotations(annotations)
  }
}
