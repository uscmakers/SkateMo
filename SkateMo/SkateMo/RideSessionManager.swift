//
//  RideSessionManager.swift
//  SkateMo
//

import Combine
import CoreLocation
import Foundation

final class RideSessionManager: ObservableObject {
    let locationManager: LocationManager
    let navigationManager: NavigationManager
    let cameraManager: CameraManager
    let objectDetector: ObjectDetector
    let obstacleEvaluator: ObstacleEvaluator

    @Published var rideStarted = false
    @Published var isSelectingDestination = false
    @Published var rideActive = false
    @Published var destinationCoordinate: CLLocationCoordinate2D?
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var routeStatusText = "Select a destination to build a route."
    @Published private(set) var routeErrorMessage: String?

    @Published private(set) var effectiveCommand: BoardCommand = .idle
    @Published private(set) var effectiveCommandSource: BoardCommandSource = .system
    @Published private(set) var effectiveCommandText = BoardCommand.idle.displayText
    @Published private(set) var isVisionOverrideActive = false
    @Published private(set) var lastNavigationCommand: BoardCommand = .idle
    @Published private(set) var obstacleStatusText = "Path clear"
    @Published private(set) var bannerCommand: BoardCommand = .idle
    @Published private(set) var bannerTitle = BoardCommand.idle.displayText
    @Published private(set) var bannerSubtitle = "Source: System. Select a destination to build a route."

    private var cancellables = Set<AnyCancellable>()
    private var hasActivatedServices = false
    private let routePlanner: CampusRoutePlanner?

    init(
        locationManager: LocationManager = LocationManager(),
        navigationManager: NavigationManager = NavigationManager(),
        cameraManager: CameraManager = CameraManager(),
        objectDetector: ObjectDetector = ObjectDetector(),
        obstacleEvaluator: ObstacleEvaluator = ObstacleEvaluator()
    ) {
        self.locationManager = locationManager
        self.navigationManager = navigationManager
        self.cameraManager = cameraManager
        self.objectDetector = objectDetector
        self.obstacleEvaluator = obstacleEvaluator
        self.routePlanner = try? CampusRoutePlanner()

        configureServices()
        configureBindings()
        updateBannerPresentation()
    }

    func activateServicesIfNeeded() {
        guard !hasActivatedServices else { return }
        hasActivatedServices = true

        locationManager.requestPermission()
        locationManager.startUpdating()
    }

    func beginRideSetup() {
        rideStarted = true
    }

    func beginDestinationSelection() {
        guard rideStarted else { return }
        isSelectingDestination = true
    }

    func setDestination(_ coordinate: CLLocationCoordinate2D) {
        destinationCoordinate = coordinate
        isSelectingDestination = false
        previewRouteIfPossible()
    }

    func startRide() {
        guard let destinationCoordinate else { return }
        guard let currentLocation = locationManager.location?.coordinate else {
            routeErrorMessage = "Current GPS location is not available yet."
            routeStatusText = "Waiting for current location."
            print("[RideSession] Cannot start route: current GPS location unavailable.")
            return
        }
        guard let routePlanner else {
            routeErrorMessage = RoutePlanningError.graphUnavailable.localizedDescription
            routeStatusText = "Route graph unavailable."
            print("[RideSession] Cannot start route: USC graph missing from bundle.")
            return
        }

        let plannedRoute: PlannedRoute
        do {
            plannedRoute = try routePlanner.route(
                from: currentLocation,
                to: destinationCoordinate,
                travelHeadingDegrees: locationManager.travelHeadingDegrees
            )
        } catch {
            routeErrorMessage = error.localizedDescription
            routeStatusText = error.localizedDescription
            rideActive = false
            print("[RideSession] Route planning failed: \(error.localizedDescription)")
            return
        }

        rideActive = true
        isSelectingDestination = false
        routeCoordinates = plannedRoute.coordinates
        routeErrorMessage = nil
        routeStatusText = String(
            format: "Route ready: %.0fft, %d nav steps over %d path nodes",
            plannedRoute.totalDistanceFeet,
            plannedRoute.navigationStepCount,
            plannedRoute.coordinates.count
        )
        navigationManager.startNavigation(with: plannedRoute.waypoints)
        cameraManager.start()
        updateEffectiveCommand()

        print("[RideSession] Ride started with destination: \(destinationCoordinate.latitude), \(destinationCoordinate.longitude)")
        print("[RideSession] Planned \(plannedRoute.navigationStepCount) navigation steps over \(plannedRoute.coordinates.count) graph nodes and \(plannedRoute.totalDistanceFeet) ft")
        print("[RideSession] Start edge: \(plannedRoute.startEdgeRoadName) [\(plannedRoute.startEdgeHighwayTypes.joined(separator: ", "))]")
        print("[RideSession] Destination edge: \(plannedRoute.endEdgeRoadName) [\(plannedRoute.endEdgeHighwayTypes.joined(separator: ", "))]")
        if let firstSegmentBearingDegrees = plannedRoute.firstSegmentBearingDegrees {
            print(String(format: "[RideSession] First segment bearing: %.1f degrees", firstSegmentBearingDegrees))
        }
        for (index, waypoint) in plannedRoute.waypoints.enumerated() {
            print("[RideSession] Waypoint \(index): \(waypoint.displayLabel) at \(waypoint.name)")
        }
        for maneuverDescription in plannedRoute.maneuverDebugDescriptions {
            print("[RideSession] \(maneuverDescription)")
        }
        updateBannerPresentation()
    }

    var commandStatusText: String {
        bannerSubtitle
    }

    static func resolveCommand(
        rideActive: Bool,
        navigationCommand: BoardCommand,
        obstacleState: ObstacleState,
        previousLastNavigationCommand: BoardCommand
    ) -> (effectiveCommand: BoardCommand, source: BoardCommandSource, cachedNavigationCommand: BoardCommand) {
        let cachedNavigationCommand = navigationCommand.isNavigationMovementCommand ? navigationCommand : previousLastNavigationCommand

        guard rideActive else {
            return (.idle, .system, cachedNavigationCommand)
        }

        if navigationCommand == .arrived {
            return (.arrived, .system, cachedNavigationCommand)
        }

        if obstacleState == .stop {
            return (.stopForObstacle, .vision, cachedNavigationCommand)
        }

        if navigationCommand == .idle, cachedNavigationCommand.isNavigationMovementCommand {
            return (cachedNavigationCommand, .navigation, cachedNavigationCommand)
        }

        let source: BoardCommandSource = navigationCommand == .idle ? .system : .navigation
        return (navigationCommand, source, cachedNavigationCommand)
    }

    private func configureServices() {
        locationManager.onLocationUpdate = { [weak self] location in
            self?.navigationManager.updateLocation(location)
        }

        cameraManager.onFrameCaptured = { [weak self] pixelBuffer in
            self?.objectDetector.detect(pixelBuffer: pixelBuffer)
        }
    }

    private func configureBindings() {
        objectDetector.$detections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detections in
                self?.obstacleEvaluator.update(with: detections)
            }
            .store(in: &cancellables)

        locationManager.$location
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.destinationCoordinate != nil, !self.rideActive else { return }
                self.previewRouteIfPossible()
            }
            .store(in: &cancellables)

        locationManager.$travelHeadingDegrees
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.destinationCoordinate != nil, !self.rideActive else { return }
                self.previewRouteIfPossible()
            }
            .store(in: &cancellables)

        navigationManager.$currentBoardCommand
            .receive(on: DispatchQueue.main)
            .sink { [weak self] command in
                guard let self = self else { return }
                if command.isNavigationMovementCommand {
                    self.lastNavigationCommand = command
                }
                print("[RideSession] Navigation command -> \(command.displayText)")
                self.updateEffectiveCommand()
            }
            .store(in: &cancellables)

        navigationManager.$nextInstructionDisplayText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateBannerPresentation()
            }
            .store(in: &cancellables)

        navigationManager.$activeManeuverAnnouncement
            .receive(on: DispatchQueue.main)
            .sink { [weak self] announcement in
                if let announcement {
                    print("[RideSession] Banner maneuver -> \(announcement.title)")
                }
                self?.updateBannerPresentation()
            }
            .store(in: &cancellables)

        obstacleEvaluator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateObstacleStatusText()
                self?.updateEffectiveCommand()
            }
            .store(in: &cancellables)

        obstacleEvaluator.$nearestObstacleDistanceMeters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateObstacleStatusText()
            }
            .store(in: &cancellables)
    }

    private func updateObstacleStatusText() {
        switch obstacleEvaluator.state {
        case .go:
            obstacleStatusText = "Path clear"
        case .caution:
            if let nearest = obstacleEvaluator.nearestObstacleDistanceMeters {
                obstacleStatusText = String(format: "Obstacle detected ahead (%.1fm)", nearest)
            } else {
                obstacleStatusText = "Obstacle detected ahead"
            }
        case .stop:
            if let nearest = obstacleEvaluator.nearestObstacleDistanceMeters {
                obstacleStatusText = String(format: "Stopping for obstacle (%.1fm)", nearest)
            } else {
                obstacleStatusText = "Stopping for obstacle"
            }
        }
        updateBannerPresentation()
    }

    private func updateEffectiveCommand() {
        let previousCommand = effectiveCommand
        let previousOverride = isVisionOverrideActive

        let resolved = Self.resolveCommand(
            rideActive: rideActive,
            navigationCommand: navigationManager.currentBoardCommand,
            obstacleState: obstacleEvaluator.state,
            previousLastNavigationCommand: lastNavigationCommand
        )

        lastNavigationCommand = resolved.cachedNavigationCommand
        effectiveCommand = resolved.effectiveCommand
        effectiveCommandSource = resolved.source
        effectiveCommandText = resolved.effectiveCommand.displayText
        isVisionOverrideActive = resolved.source == .vision

        if !previousOverride, isVisionOverrideActive {
            print("[RideSession] Vision override engaged. Effective command -> \(effectiveCommand.displayText)")
        } else if previousOverride, !isVisionOverrideActive {
            print("[RideSession] Vision override cleared. Resuming \(effectiveCommand.displayText)")
        } else if previousCommand != effectiveCommand {
            print("[RideSession] Effective command -> \(effectiveCommand.displayText) [\(effectiveCommandSource.displayText)]")
        }

        updateBannerPresentation()
    }

    private func updateBannerPresentation() {
        if isVisionOverrideActive {
            bannerCommand = effectiveCommand
            bannerTitle = effectiveCommandText
            bannerSubtitle = "Source: \(effectiveCommandSource.displayText). \(obstacleStatusText)"
            return
        }

        if rideActive, let announcement = navigationManager.activeManeuverAnnouncement {
            bannerCommand = announcement.command
            bannerTitle = announcement.title

            if navigationManager.nextInstructionDisplayText.isEmpty {
                bannerSubtitle = "Source: Navigation. \(announcement.subtitle)"
            } else {
                bannerSubtitle = "Source: Navigation. \(announcement.subtitle). Next: \(navigationManager.nextInstructionDisplayText)"
            }
            return
        }

        bannerCommand = effectiveCommand
        bannerTitle = effectiveCommandText

        if !rideActive {
            if let routeErrorMessage {
                bannerSubtitle = "Source: \(effectiveCommandSource.displayText). \(routeErrorMessage)"
            } else {
                bannerSubtitle = "Source: \(effectiveCommandSource.displayText). \(routeStatusText)"
            }
            return
        }

        if effectiveCommand == .arrived {
            bannerSubtitle = "Source: \(effectiveCommandSource.displayText). Destination reached."
            return
        }

        if navigationManager.nextInstructionDisplayText.isEmpty {
            bannerSubtitle = "Source: \(effectiveCommandSource.displayText). Following route."
        } else {
            bannerSubtitle = "Source: \(effectiveCommandSource.displayText). Next: \(navigationManager.nextInstructionDisplayText)"
        }
    }

    private func previewRouteIfPossible() {
        guard !rideActive else { return }
        guard let destinationCoordinate else {
            routeCoordinates = []
            routeErrorMessage = nil
            routeStatusText = "Select a destination to build a route."
            updateBannerPresentation()
            return
        }
        guard let currentLocation = locationManager.location?.coordinate else {
            routeCoordinates = []
            routeErrorMessage = nil
            routeStatusText = "Destination selected. Waiting for current location."
            updateBannerPresentation()
            return
        }
        guard let routePlanner else {
            routeCoordinates = []
            routeErrorMessage = RoutePlanningError.graphUnavailable.localizedDescription
            routeStatusText = "Route graph unavailable."
            updateBannerPresentation()
            return
        }

        do {
            let plannedRoute = try routePlanner.route(
                from: currentLocation,
                to: destinationCoordinate,
                travelHeadingDegrees: locationManager.travelHeadingDegrees
            )
            routeCoordinates = plannedRoute.coordinates
            routeErrorMessage = nil
            routeStatusText = String(
                format: "Preview: %.0fft, %d nav steps over %d path nodes",
                plannedRoute.totalDistanceFeet,
                plannedRoute.navigationStepCount,
                plannedRoute.coordinates.count
            )
            updateBannerPresentation()
        } catch {
            routeCoordinates = []
            routeErrorMessage = error.localizedDescription
            routeStatusText = error.localizedDescription
            updateBannerPresentation()
        }
    }
}
