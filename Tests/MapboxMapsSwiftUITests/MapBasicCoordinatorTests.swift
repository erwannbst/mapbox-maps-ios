import CoreLocation
@_spi(Package) @testable import MapboxMaps
@_spi(Experimental) @testable import MapboxMapsSwiftUI

import XCTest

@available(iOS 13.0, *)
final class MapBasicCoordinatorTests: XCTestCase {
    var mapView: MockMapView!
    var setCameraStub: Stub<CameraState, Void>!
    var me: MapBasicCoordinator!

    override func setUpWithError() throws {
        mapView = MockMapView()
        setCameraStub = Stub()
        me = MapBasicCoordinator(setCamera: setCameraStub.call(with:))
        me.setMapView(mapView.facade)
    }

    override func tearDownWithError() throws {
        mapView = nil
        me = nil
        setCameraStub = nil
    }

    func testUpstreamCameraUpdate() {
        let event = CameraChanged(cameraState: .random(), timestamp: Date())
        mapView.mapboxMap.events.onCameraChanged.send(event)
        XCTAssertEqual(setCameraStub.invocations.count, 1)

        mapView.mapboxMap.events.onCameraChanged.send(event)
        mapView.mapboxMap.events.onCameraChanged.send(event)
        XCTAssertEqual(setCameraStub.invocations.count, 3)
    }

    func testDownstreamCameraUpdate() {
        me.update(
            camera: nil,
            deps: MapDependencies(),
            colorScheme: .light)
        XCTAssertEqual(mapView.mapboxMap.setCameraStub.invocations.count, 0)

        let cameraState = CameraState.random()
        me.update(
            camera: cameraState,
            deps: MapDependencies(),
            colorScheme: .light)
        XCTAssertEqual(mapView.mapboxMap.setCameraStub.invocations.count, 1)
        XCTAssertEqual(mapView.mapboxMap.setCameraStub.invocations.first?.parameters, CameraOptions(cameraState: cameraState))
    }

    func testCameraBounds() {
        let cameraBounds = CameraBoundsOptions(bounds: CoordinateBounds(southwest: .random(), northeast: .random()))
        me.update(
            camera: nil,
            deps: MapDependencies(cameraBounds: cameraBounds),
            colorScheme: .light)
        XCTAssertEqual(mapView.mapboxMap.setCameraBoundsStub.invocations.count, 1)
        XCTAssertEqual(mapView.mapboxMap.setCameraBoundsStub.invocations.first?.parameters, cameraBounds)
    }

    func testStyleURI() {
        let uris = MapDependencies.StyleURIs(default: .light, darkMode: .dark)

        me.update(
            camera: nil,
            deps: MapDependencies(styleURIs: uris),
            colorScheme: .light)
        var invocations = mapView.style.$uri.setStub.invocations
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations.first?.parameters, .light)

        me.update(
            camera: nil,
            deps: MapDependencies(styleURIs: uris),
            colorScheme: .light)
        invocations = mapView.style.$uri.setStub.invocations
        XCTAssertEqual(invocations.count, 1, "Setting same style URI doesn't change it")

        me.update(
            camera: nil,
            deps: MapDependencies(styleURIs: uris),
            colorScheme: .dark)
        invocations = mapView.style.$uri.setStub.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[1].parameters, .dark)
    }

    func testMapOptions() {
        me.update(
            camera: nil,
            deps: MapDependencies(),
            colorScheme: .light)

        let mapboxMap = mapView.mapboxMap
        // Setting to already existing valuesa doesn't change it
        XCTAssertEqual(mapboxMap.northOrientationStub.invocations.count, 0)
        XCTAssertEqual(mapboxMap.setConstraintModeStub.invocations.count, 0)
        XCTAssertEqual(mapboxMap.setViewportModeStub.invocations.count, 0)

        me.update(
            camera: nil,
            deps: MapDependencies(
                constrainMode: .none,
                viewportMode: .flippedY,
                orientation: .downwards),
            colorScheme: .light)
        XCTAssertEqual(mapboxMap.setConstraintModeStub.invocations.count, 1)
        XCTAssertEqual(mapboxMap.setViewportModeStub.invocations.count, 1)
        XCTAssertEqual(mapboxMap.northOrientationStub.invocations.count, 1)

        XCTAssertEqual(mapboxMap.setConstraintModeStub.invocations.first?.parameters, ConstrainMode.none)
        XCTAssertEqual(mapboxMap.setViewportModeStub.invocations.first?.parameters, .flippedY)
        XCTAssertEqual(mapboxMap.northOrientationStub.invocations.first?.parameters, .downwards)
    }

    func testTapGesture() {
        let mockActions = MockActions()
        let deps = MapDependencies(actions: mockActions.actions)
        me.update(camera: nil, deps: deps, colorScheme: .light)

        let point = CGPoint.random()
        let coordinate = CLLocationCoordinate2D.random()

        let locStub = mapView.locationsStub
        locStub.defaultReturnValue = point
        mapView.mapboxMap.coordinateForPointStub.defaultReturnValue = coordinate

        mapView.gestures.singleTapGestureRecognizerMock.sendActions()

        XCTAssertEqual(locStub.invocations.count, 1)
        XCTAssertEqual(locStub.invocations.first?.parameters, mapView.gestures.singleTapGestureRecognizerMock)
        XCTAssertEqual(mockActions.onMapTapGesture.invocations.count, 1)
        XCTAssertEqual(mockActions.onMapTapGesture.invocations.first?.parameters, point)

        let qrfStub = mapView.mapboxMap.qrfStub
        XCTAssertEqual(qrfStub.invocations.count, 1)
        XCTAssertEqual(qrfStub.invocations.first?.parameters.point, point)
        XCTAssertEqual(qrfStub.invocations.first?.parameters.options?.layerIds, ["layer-foo"])

        let feature = Feature(geometry: Point(coordinate))
        let queriedRenderedFeature = QueriedRenderedFeature(
            __queriedFeature: QueriedFeature(
                __feature: MapboxCommon.Feature(feature),
                source: "src",
                sourceLayer: "src-layer",
                state: [String: Any]()),
            layers: [])
        qrfStub.invocations.first?.parameters.completion(.success([queriedRenderedFeature]))
        XCTAssertEqual(mockActions.onLayerTapAction.invocations.count, 1)
        XCTAssertEqual(mockActions.onLayerTapAction.invocations.first?.parameters.point, point)
        XCTAssertEqual(mockActions.onLayerTapAction.invocations.first?.parameters.features, [queriedRenderedFeature])
        XCTAssertEqual(mockActions.onLayerTapAction.invocations.first?.parameters.coordinate, coordinate)
    }

    func testTapGestureMissLayer() {
        let mockActions = MockActions()
        let deps = MapDependencies(actions: mockActions.actions)
        me.update(camera: nil, deps: deps, colorScheme: .light)

        mapView.gestures.singleTapGestureRecognizerMock.sendActions()

        mapView.mapboxMap.qrfStub.invocations.first?.parameters.completion(.success([]))
        XCTAssertEqual(mockActions.onLayerTapAction.invocations.count, 0)

        mapView.gestures.singleTapGestureRecognizerMock.sendActions()

        mapView.mapboxMap.qrfStub.invocations[1].parameters.completion(.failure(MapError(coreError: "foo")))
        XCTAssertEqual(mockActions.onLayerTapAction.invocations.count, 0)
    }

    func testNotifyMapEventsToObservers() {
        var observedMapLoaded: MapLoaded?
        let subscription = AnyEventSubscription(keyPath: \.onMapLoaded) { event in
            observedMapLoaded = event
        }
        let deps = MapDependencies(eventsSubscriptions: [subscription])

        me.update(camera: nil, deps: deps, colorScheme: .light)
        let mapLoaded = MapLoaded(timeInterval: EventTimeInterval(begin: Date(), end: Date()))

        mapView.mapboxMap.events.onMapLoaded.send(mapLoaded)
        XCTAssertEqual(mapLoaded, observedMapLoaded)
    }
}

@available(iOS 13.0, *)
struct MockActions {
    var onMapTapGesture = Stub<CGPoint, Void>()
    var onLayerTapAction = Stub<MapLayerTapPayload, Void>()

    var actions: MapDependencies.Actions {
        .init(
            onMapTapGesture: onMapTapGesture.call(with:),
            layerTapActions: [
                (["layer-foo"], onLayerTapAction.call(with:))
            ])
    }
}
