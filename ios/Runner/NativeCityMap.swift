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
  private let overviewRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 39.0, longitude: 22.9),
    span: MKCoordinateSpan(latitudeDelta: 7.5, longitudeDelta: 7.5)
  )

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
    mapView.setRegion(overviewRegion, animated: false)
    channel = FlutterMethodChannel(name: "neat/native_city_map_channel", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "zoomOut" {
        self?.zoomOut()
      }
      result(nil)
    }

    if let dict = args as? [String: Any],
       let cities = dict["cities"] as? [[String: Any]] {
      addAnnotations(cities)
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
    view.canShowCallout = false
    return view
  }

  func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
    guard let annotation = view.annotation, let city = annotation.title ?? nil else { return }
    let region = MKCoordinateRegion(
      center: annotation.coordinate,
      latitudinalMeters: 70_000,
      longitudinalMeters: 70_000
    )
    mapView.setRegion(region, animated: true)
    channel?.invokeMethod("citySelected", arguments: city)
  }

  private func zoomOut() {
    for annotation in mapView.selectedAnnotations {
      mapView.deselectAnnotation(annotation, animated: false)
    }
    mapView.setRegion(overviewRegion, animated: true)
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
}
