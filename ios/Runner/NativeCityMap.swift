import Flutter
import MapKit
import UIKit

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
    NativeCityMapView(
      frame: frame,
      viewId: viewId,
      args: args,
      messenger: messenger
    )
  }
}

final class NativeCityMapView: NSObject, FlutterPlatformView, MKMapViewDelegate {
  private let mapView = MKMapView()
  private var channel: FlutterMethodChannel?

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    super.init()
    mapView.frame = frame
    mapView.delegate = self
    mapView.isRotateEnabled = false
    mapView.isPitchEnabled = false
    mapView.showsCompass = false
    mapView.showsScale = false
    mapView.showsTraffic = false
    mapView.pointOfInterestFilter = .excludingAll
    mapView.overrideUserInterfaceStyle = .dark
    mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "city")
    channel = FlutterMethodChannel(name: "neat/native_city_map_channel", binaryMessenger: messenger)

    if let dict = args as? [String: Any],
       let cities = dict["cities"] as? [[String: Any]] {
      addAnnotations(cities)
      if let selected = dict["selectedCity"] as? String {
        focus(on: selected, cities: cities)
      }
    }
  }

  func view() -> UIView {
    mapView
  }

  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    guard annotation is MKPointAnnotation else { return nil }
    let view = mapView.dequeueReusableAnnotationView(withIdentifier: "city", for: annotation) as! MKMarkerAnnotationView
    view.markerTintColor = UIColor.systemGreen
    view.glyphImage = UIImage(systemName: "mappin")
    view.canShowCallout = true
    return view
  }

  func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
    guard let city = view.annotation?.title ?? nil else { return }
    channel?.invokeMethod("citySelected", arguments: city)
  }

  private func addAnnotations(_ cities: [[String: Any]]) {
    for city in cities {
      guard
        let name = city["name"] as? String,
        let latitude = city["latitude"] as? Double,
        let longitude = city["longitude"] as? Double
      else { continue }

      let annotation = MKPointAnnotation()
      annotation.title = name
      annotation.coordinate = CLLocationCoordinate2D(
        latitude: latitude,
        longitude: longitude
      )
      mapView.addAnnotation(annotation)
    }
  }

  private func focus(on selected: String, cities: [[String: Any]]) {
    guard
      let city = cities.first(where: { ($0["name"] as? String) == selected }),
      let latitude = city["latitude"] as? Double,
      let longitude = city["longitude"] as? Double
    else { return }

    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let region = MKCoordinateRegion(
      center: coordinate,
      latitudinalMeters: 650_000,
      longitudinalMeters: 650_000
    )
    mapView.setRegion(region, animated: false)
  }
}
