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

    @Published private(set) var effectiveCommand: BoardCommand = .idle
    @Published private(set) var effectiveCommandSource: BoardCommandSource = .system
    @Published private(set) var effectiveCommandText = BoardCommand.idle.displayText
    @Published private(set) var isVisionOverrideActive = false
    @Published private(set) var lastNavigationCommand: BoardCommand = .idle
    @Published private(set) var obstacleStatusText = "Path clear"

    private var cancellables = Set<AnyCancellable>()
    private var hasActivatedServices = false

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

        configureServices()
        configureBindings()
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
    }

    func startRide() {
        guard let destinationCoordinate else { return }

        rideActive = true
        isSelectingDestination = false
        navigationManager.startNavigation(with: sampleWaypoints(to: destinationCoordinate))
        cameraManager.start()
        updateEffectiveCommand()

        print("[RideSession] Ride started with destination: \(destinationCoordinate.latitude), \(destinationCoordinate.longitude)")
    }

    var commandStatusText: String {
        if isVisionOverrideActive {
            return "Source: \(effectiveCommandSource.displayText). \(obstacleStatusText)"
        }

        if !rideActive {
            return "Source: \(effectiveCommandSource.displayText). Start a ride to activate navigation + safety."
        }

        if effectiveCommand == .arrived {
            return "Source: \(effectiveCommandSource.displayText). Destination reached."
        }

        if navigationManager.currentInstruction.isEmpty {
            return "Source: \(effectiveCommandSource.displayText). Following route."
        }

        return "Source: \(effectiveCommandSource.displayText). Instruction: \(navigationManager.currentInstruction.uppercased())"
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
    }

    private func sampleWaypoints(to destinationCoordinate: CLLocationCoordinate2D) -> [Waypoint] {
        [
            Waypoint(
                name: "Start Point",
                coordinate: CLLocationCoordinate2D(latitude: 34.0211, longitude: -118.2870),
                action: .start
            ),
            Waypoint(
                name: "West 34th & Watt Way",
                coordinate: CLLocationCoordinate2D(latitude: 34.0195, longitude: -118.2879),
                action: .right
            ),
            Waypoint(
                name: "Destination",
                coordinate: destinationCoordinate,
                action: .destination
            )
        ]
    }
}
