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

// MARK: - Annotation

/// A city pin, carrying the two things that decide how it is drawn: who it
/// beats when two pins want the same patch of screen, and how busy the city
/// currently is.
final class CityAnnotation: MKPointAnnotation {
  /// 0-1000, sent from `GreeceCity.displayPriority`.
  var priority: Int = 400
  var heat: Double = 0
}

// MARK: - Platform View

final class NativeCityMapView: NSObject, FlutterPlatformView, MKMapViewDelegate {
  private let map = MKMapView()
  private var channel: FlutterMethodChannel?

  /// Every city, best known first, whether or not it is currently on the map.
  /// Decluttering adds and removes annotations rather than hiding their views:
  /// MapKit only creates a view once an annotation is near the viewport, so a
  /// hidden-view approach leaves pins that scroll into range visible again
  /// regardless of what filtered them out.
  private var allCities: [CityAnnotation] = []

  /// The map that incoming calls apply to.
  ///
  /// Every instance registers a handler under the same channel name, so only
  /// the newest registration is live — and a call meant for the map on screen
  /// could land on an older, off-screen one instead. zoomOut going astray is
  /// what left a map locked with nothing able to release it. Weak so a
  /// dismissed map does not keep itself alive as the target.
  private static weak var current: NativeCityMapView?

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
    NativeCityMapView.current = self
  }

  func view() -> UIView { map }

  // MARK: MKMapViewDelegate

  func mapView(_ mv: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    guard annotation is MKPointAnnotation else { return nil }
    let v = mv.dequeueReusableAnnotationView(
      withIdentifier: "pin", for: annotation
    ) as! MKMarkerAnnotationView
    v.markerTintColor = UIColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1) // always green
    v.glyphImage = UIImage(systemName: "mappin")
    v.canShowCallout = false
    // Spacing is decided in `applyDeclutter()`, which knows the pin's exact
    // screen position; MapKit's own collision handling would only second-guess
    // it with a different footprint, so every pin it is handed is required.
    v.displayPriority = .required
    return v
  }

  /// Re-fills the map every time the camera settles: which cities fit depends
  /// entirely on where the camera is now.
  func mapView(_ mv: MKMapView, regionDidChangeAnimated animated: Bool) {
    let span = mv.region.span.latitudeDelta
    guard span > 0, !span.isNaN else { return }
    // Arrival is what starts the next leg of an automatic journey; see
    // advanceFlight(). Harmless when nothing is in flight.
    if isFlying { advanceFlight() }
    applyDeclutter()
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

    // The user has chosen; any journey still running was a guess and must not
    // keep moving the map out from under them.
    cancelFlight()
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
    // Searched across every city, not just the pins currently on the map.
    // `applyDeclutter()` keeps `map.annotations` down to what actually fits on
    // screen, so at the country view most cities are not in it — and looking
    // there meant the journey silently never started for exactly the smaller
    // cities that most need showing.
    guard let annotation = allCities.first(where: { $0.title == name })
      ?? (map.annotations.first { ($0.title ?? nil) == name })
    else { return }

    let target = annotation.coordinate

    // Four beats, so it reads as a journey rather than a cut: settle at the
    // whole country, glide across to the city at that same height so the
    // distance is visible, then come down in two stages rather than dropping.
    //
    // Deliberately does not select the annotation — that would fire didSelect,
    // report back to Flutter as though the pin had been tapped, and drop the
    // card over the animation this exists to show.
    var stages: [MKCoordinateRegion] = []
    // Only if we are not effectively there already: a no-op setRegion may
    // never report back, and starting the chain on one would stall it.
    if !isNear(map.region, overview) { stages.append(overview) }
    stages.append(MKCoordinateRegion(center: target, span: overview.span))
    stages.append(MKCoordinateRegion(
      center: target, latitudinalMeters: 220_000, longitudinalMeters: 220_000))
    stages.append(MKCoordinateRegion(
      center: target, latitudinalMeters: 70_000, longitudinalMeters: 70_000))
    beginFlight(stages)
  }

  // MARK: Flight

  /// Remaining legs of an automatic journey, flown one at a time.
  ///
  /// Each leg starts only once the previous one has actually arrived. The old
  /// version fired all three off `asyncAfter` on fixed delays, which is what
  /// made this look instant: a `setRegion` issued while MapKit is still
  /// animating does not queue behind it, it replaces it — so the legs
  /// cancelled each other and the map cut straight to the city.
  private var flightQueue: [MKCoordinateRegion] = []
  private var flightGeneration = 0
  private var flightWatchdog: DispatchWorkItem?

  private func beginFlight(_ stages: [MKCoordinateRegion]) {
    flightGeneration &+= 1
    flightQueue = stages
    advanceFlight()
  }

  private func cancelFlight() {
    flightGeneration &+= 1
    flightQueue = []
    flightWatchdog?.cancel()
    flightWatchdog = nil
  }

  private var isFlying: Bool { !flightQueue.isEmpty || flightWatchdog != nil }

  private func advanceFlight() {
    flightWatchdog?.cancel()
    flightWatchdog = nil
    guard !flightQueue.isEmpty else { return }
    let next = flightQueue.removeFirst()

    // MapKit reports arrival through regionDidChangeAnimated, which is what
    // normally drives the next leg. A leg that moves the camera too little to
    // animate may never report, so each one also carries its own deadline.
    let generation = flightGeneration
    let watchdog = DispatchWorkItem { [weak self] in
      guard let self, self.flightGeneration == generation else { return }
      self.flightWatchdog = nil
      self.advanceFlight()
    }
    flightWatchdog = watchdog
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.legTimeout, execute: watchdog)

    map.setRegion(next, animated: true)
  }

  /// Longest a single leg is allowed to take before the next one starts
  /// regardless. Comfortably above MapKit's own animation, so in practice
  /// arrival drives the chain and this only rescues a leg that never moved.
  static let legTimeout = 1.1

  /// Whether two regions are close enough that animating between them would
  /// not read as movement.
  private func isNear(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
    abs(a.center.latitude - b.center.latitude) < 0.05
      && abs(a.center.longitude - b.center.longitude) < 0.05
      && abs(a.span.latitudeDelta - b.span.latitudeDelta) < 0.5
  }

  private func zoomOut() {
    cancelFlight()
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
    // Routed to `current`, not to `self`: whichever instance registered the
    // live handler may not be the map the user is looking at.
    channel?.setMethodCallHandler { call, result in
      let target = NativeCityMapView.current
      if call.method == "zoomOut" { target?.zoomOut() }
      if call.method == "focusCity", let name = call.arguments as? String {
        target?.focusCity(named: name)
      }
      if call.method == "updateColorScheme", let isDark = call.arguments as? Bool {
        target?.map.overrideUserInterfaceStyle = isDark ? .dark : .light
      }
      if call.method == "updateHeat" {
        // Values arrive as NSNumber over the channel, so read them loosely
        // rather than forcing [String: Double] and dropping the lot on a
        // single integer 0 or 1.
        let raw = (call.arguments as? [String: Any]) ?? [:]
        target?.updateHeat(raw.compactMapValues { ($0 as? NSNumber)?.doubleValue })
      }
      result(nil)
    }
  }

  private func loadCities(from args: Any?) {
    guard
      let dict   = args as? [String: Any],
      let cities = dict["cities"] as? [[String: Any]]
    else { return }

    allCities = cities.compactMap { c in
      guard
        let name = c["name"]      as? String,
        let lat  = c["latitude"]  as? Double,
        let lng  = c["longitude"] as? Double
      else { return nil }
      let a = CityAnnotation()
      a.title = name
      a.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
      // An unlabelled city ranks below every labelled one rather than above.
      a.priority = (c["priority"] as? Int) ?? 0
      return a
    }
    // Best known first: decluttering walks this order and the first pin to
    // claim a patch of screen keeps it.
    allCities.sort { $0.priority > $1.priority }
    applyDeclutter()

    // The view is usually still frameless here, and a projection against a
    // zero-size map places nothing — so try again as it settles into its real
    // size. Each pass is idempotent, and the first region change takes over
    // from there. (The Android page does the same, for the same reason.)
    for delay in [0.3, 0.8, 2.0] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        self?.applyDeclutter()
      }
    }
  }

  // MARK: Decluttering

  /// How far apart two pin centres have to be, in points — the marker's own
  /// footprint, so pins may touch but never cover one another. Wider than it
  /// is tall would be wrong here: a marker is a balloon, taller than it is
  /// wide, and treating it as a circle wasted the horizontal room that Greece,
  /// being a wide country on a narrow screen, has least of.
  private static let minimumPinGapX: CGFloat = 38
  private static let minimumPinGapY: CGFloat = 46

  /// Pins beyond the edge are still placed, so panning a short way doesn't
  /// pop a new one into existence at the moment it crosses the boundary.
  private static let offscreenMargin: CGFloat = 80

  /// Fills the map with every city that fits.
  ///
  /// Cities are taken best-known first and each one is kept unless its marker
  /// would overlap one already placed — so Θεσσαλονίκη is always there and the
  /// town beside it appears the moment the camera comes down far enough for
  /// them both to have room. Nothing is gated on a zoom threshold: how much
  /// you see is decided by how much space there is.
  private func applyDeclutter() {
    let bounds = map.bounds.insetBy(dx: -Self.offscreenMargin, dy: -Self.offscreenMargin)
    guard bounds.width > 1, bounds.height > 1 else { return }

    var placed: [CGPoint] = []
    var wanted = Set<ObjectIdentifier>()

    for city in allCities {
      let point = map.convert(city.coordinate, toPointTo: map)
      guard point.x.isFinite, point.y.isFinite, bounds.contains(point) else { continue }
      let collides = placed.contains { other in
        let dx = (point.x - other.x) / Self.minimumPinGapX
        let dy = (point.y - other.y) / Self.minimumPinGapY
        return dx * dx + dy * dy < 1
      }
      if collides { continue }
      placed.append(point)
      wanted.insert(ObjectIdentifier(city))
    }

    // Never pull a pin out from under an open card: its annotation is still
    // selected, and removing it deselects with no way back to the card.
    for annotation in map.selectedAnnotations {
      wanted.insert(ObjectIdentifier(annotation))
    }

    let onMap = Set(map.annotations.compactMap { $0 as? CityAnnotation }.map { ObjectIdentifier($0) })
    let toAdd = allCities.filter { wanted.contains(ObjectIdentifier($0)) && !onMap.contains(ObjectIdentifier($0)) }
    let toRemove = allCities.filter { !wanted.contains(ObjectIdentifier($0)) && onMap.contains(ObjectIdentifier($0)) }

    if !toRemove.isEmpty { map.removeAnnotations(toRemove) }
    if !toAdd.isEmpty { map.addAnnotations(toAdd) }
  }

  // MARK: Heat

  /// Pins are always green — heat updates are ignored.
  private func updateHeat(_ values: [String: Double]) {}
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
