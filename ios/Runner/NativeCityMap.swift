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

    // No interaction lock here. While the card is up the Flutter overlay
    // already swallows every touch before it reaches this view, so a lock adds
    // nothing — but it made the map's only unlock path a round trip through
    // Flutter (zoomOut(), reached solely from the card's close/join handlers).
    // Any selection that did not end in a visible card therefore froze the map
    // for good: interaction off, no card to dismiss, nothing left to call
    // zoomOut. The Android map has never had a lock for exactly this reason.
    focus(on: annotation.coordinate)
    channel?.invokeMethod("citySelected", arguments: name)
  }

  // MARK: Private

  /// The close-in region used whenever a city becomes the subject, whether
  /// the user tapped its pin or we picked it from their location.
  private func focus(on coordinate: CLLocationCoordinate2D) {
    map.setRegion(
      MKCoordinateRegion(
        center: coordinate,
        latitudinalMeters: 70_000,
        longitudinalMeters: 70_000
      ),
      animated: true
    )
  }

  /// Zooms to a city by name without waiting for a tap, so sign-up can travel
  /// to the city it detected instead of the card appearing over an untouched
  /// map of the whole country.
  private func focusCity(named name: String) {
    guard let annotation = map.annotations.first(where: {
      ($0.title ?? nil) == name
    }) else { return }

    // Flown in two stages so it reads as travel rather than a cut: glide
    // across the country at the height you were already at, then descend once
    // the city is under you. A single setRegion does both at once, which is
    // over before it registers as movement.
    //
    // Deliberately does not select the annotation — that would fire
    // didSelect, report back to Flutter as though the pin had been tapped,
    // and drop the card over the animation this exists to show.
    let span = map.region.span
    map.setRegion(
      MKCoordinateRegion(center: annotation.coordinate, span: span),
      animated: true
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.travelSeconds) { [weak self] in
      self?.focus(on: annotation.coordinate)
    }
  }

  /// How long the glide runs before the descent begins. Kept here and mirrored
  /// in the Dart side's card delay so the card lands after the map settles.
  static let travelSeconds = 0.75

  private func zoomOut() {
    // Still restores interaction, though nothing disables it any more: a map
    // left locked by a previous build must come back to life on first close
    // rather than staying dead until the app is reinstalled.
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
      if call.method == "focusCity", let name = call.arguments as? String {
        self?.focusCity(named: name)
      }
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

// MARK: - Still snapshot

/// Renders a still image of the Greece overview with MKMapSnapshotter.
///
/// The city-setup screen wants the map behind its copy, but embedding the live
/// `MKMapView` there is exactly what broke it before: a full-screen Flutter
/// layer composited over a platform view leaves the map unable to pan. A
/// snapshot is a plain UIImage — it has no gesture handling to lose, so it can
/// be dimmed, overlaid and scrolled over freely. The interactive map is still
/// warmed in parallel and takes over on the next screen.
enum MapSnapshot {
  /// Tighter than the live map's opening region: the hero is a short, wide
  /// strip, and MapKit grows whichever axis it needs to fill it. The live
  /// map's 7.5-degree square would leave Greece small in a sea of Balkans.
  private static let overview = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 38.6, longitude: 24.0),
    span: MKCoordinateSpan(latitudeDelta: 5.2, longitudeDelta: 5.2)
  )

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "NeatMapSnapshot") else { return }
    let channel = FlutterMethodChannel(
      name: "neat/map_snapshot",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard
        call.method == "snapshot",
        let args = call.arguments as? [String: Any],
        let width = args["width"] as? Double,
        let height = args["height"] as? Double,
        width > 1, height > 1
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let isDark = args["isDark"] as? Bool ?? true
      let scale = args["scale"] as? Double ?? 2.0
      // Optional [[lat, lng], ...] drawn onto the still as city dots.
      let pins: [CLLocationCoordinate2D] = (args["pins"] as? [[Double]] ?? [])
        .compactMap { pair in
          guard pair.count == 2 else { return nil }
          return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
      render(
        size: CGSize(width: width, height: height),
        scale: CGFloat(scale),
        isDark: isDark,
        pins: pins
      ) { data in
        // Channel replies must happen on the platform thread; the snapshotter
        // calls back on the queue it was started with.
        DispatchQueue.main.async {
          result(data.map { FlutterStandardTypedData(bytes: $0) })
        }
      }
    }
  }

  private static func render(
    size: CGSize,
    scale: CGFloat,
    isDark: Bool,
    pins: [CLLocationCoordinate2D],
    completion: @escaping (Data?) -> Void
  ) {
    let options = MKMapSnapshotter.Options()
    options.region = overview
    options.size = size
    options.scale = scale
    options.mapType = .standard
    options.pointOfInterestFilter = .excludingAll
    options.showsBuildings = false
    options.traitCollection = UITraitCollection(
      userInterfaceStyle: isDark ? .dark : .light
    )

    MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) {
      snapshot, error in
      guard let snapshot else {
        NSLog("[MapSnapshot] failed: \(error?.localizedDescription ?? "unknown")")
        completion(nil)
        return
      }
      guard !pins.isEmpty else {
        completion(snapshot.image.pngData())
        return
      }
      completion(draw(pins: pins, on: snapshot, size: size, scale: scale).pngData())
    }
  }

  /// Stamps the city dots onto the still. MKMapSnapshotter renders tiles only —
  /// annotations are the caller's job, projected through `snapshot.point(for:)`.
  private static func draw(
    pins: [CLLocationCoordinate2D],
    on snapshot: MKMapSnapshotter.Snapshot,
    size: CGSize,
    scale: CGFloat
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = true
    let bounds = CGRect(origin: .zero, size: size)

    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      snapshot.image.draw(in: bounds)
      // The same green as the live map's markers, so the still previews what
      // the user is about to browse.
      ctx.cgContext.setFillColor(
        UIColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1).cgColor
      )
      ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
      ctx.cgContext.setLineWidth(1.2)
      let radius: CGFloat = 5.0
      for coordinate in pins {
        let point = snapshot.point(for: coordinate)
        guard bounds.insetBy(dx: -radius, dy: -radius).contains(point) else { continue }
        ctx.cgContext.addEllipse(
          in: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
          )
        )
        ctx.cgContext.drawPath(using: .fillStroke)
      }
    }
  }
}
