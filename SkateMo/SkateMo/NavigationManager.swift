//
//  NavigationManager.swift
//  SkateMo
//
//  Created by Justin Jiang on 3/6/26.
//

import Foundation
import CoreLocation

struct Waypoint {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let action: NavigationAction
    let maneuverNumber: Int?

    init(
        name: String,
        coordinate: CLLocationCoordinate2D,
        action: NavigationAction,
        maneuverNumber: Int? = nil
    ) {
        self.name = name
        self.coordinate = coordinate
        self.action = action
        self.maneuverNumber = maneuverNumber
    }

    var displayLabel: String {
        switch action {
        case .left, .right:
            if let maneuverNumber {
                return "TURN \(maneuverNumber): \(action.instructionText.uppercased())"
            }
            return action.boardCommand.displayText
        case .straight:
            if let maneuverNumber {
                return "STEP \(maneuverNumber): \(action.instructionText.uppercased())"
            }
            return action.instructionText.uppercased()
        case .destination:
            return action.instructionText.uppercased()
        case .start:
            return action.instructionText.uppercased()
        }
    }
}

struct NavigationManeuverAnnouncement: Equatable {
    let command: BoardCommand
    let title: String
    let subtitle: String
    let maneuverNumber: Int?
}

private struct ActiveTurnManeuver {
    let triggerWaypointIndex: Int
    let completionWaypointIndex: Int
    let command: BoardCommand
    let triggerCoordinate: CLLocationCoordinate2D
    let expectedExitHeadingDegrees: Double?
}

class NavigationManager: ObservableObject {
    static let defaultTurnTriggerDistanceMeters: CLLocationDistance = 15.0
    static let minimumTurnTriggerDistanceMeters: CLLocationDistance = 5.0
    static let maximumTurnTriggerDistanceMeters: CLLocationDistance = 40.0
    private static let turnTriggerDistanceDefaultsKey = "NavigationManager.turnTriggerDistanceMeters"

    let waypointLookaheadCount = 6

    // The route waypoints with instructions
    @Published var waypoints: [Waypoint] = []

    // Current waypoint index (the one we're navigating towards)
    @Published var currentWaypointIndex: Int = 0

    // Whether navigation is active
    @Published var isNavigating: Bool = false

    // Current instruction to display
    @Published var currentInstruction: String = ""
    @Published var nextInstructionText: String = ""
    @Published var nextInstructionDisplayText: String = ""
    @Published var currentBoardCommand: BoardCommand = .idle
    @Published var activeManeuverAnnouncement: NavigationManeuverAnnouncement?
    @Published private(set) var activeTurnTargetHeadingDegrees: Double?
    @Published private(set) var turnTriggerDistanceMeters: CLLocationDistance

    // Distance to next waypoint
    @Published var distanceToNextWaypoint: CLLocationDistance = 0

    private let maneuverAnnouncementDuration: TimeInterval = 1.75
    private let turnCompletionHeadingToleranceDegrees = 35.0
    private let minimumTurnCompletionTravelMeters: CLLocationDistance = 4.0
    private var clearAnnouncementWorkItem: DispatchWorkItem?
    private var activeTurnManeuver: ActiveTurnManeuver?
    private let settingsStore: UserDefaults?

    init(
        turnTriggerDistanceMeters: CLLocationDistance? = nil,
        settingsStore: UserDefaults? = .standard
    ) {
        self.settingsStore = settingsStore

        let storedDistance: CLLocationDistance?
        if let settingsStore,
           settingsStore.object(forKey: Self.turnTriggerDistanceDefaultsKey) != nil {
            storedDistance = settingsStore.double(forKey: Self.turnTriggerDistanceDefaultsKey)
        } else {
            storedDistance = nil
        }
        self.turnTriggerDistanceMeters = Self.clampedTurnTriggerDistance(
            turnTriggerDistanceMeters ?? storedDistance ?? Self.defaultTurnTriggerDistanceMeters
        )
    }

    // MARK: - Navigation Control

    func updateTurnTriggerDistance(_ distanceMeters: CLLocationDistance) {
        let clampedDistance = Self.clampedTurnTriggerDistance(distanceMeters)
        turnTriggerDistanceMeters = clampedDistance
        settingsStore?.set(clampedDistance, forKey: Self.turnTriggerDistanceDefaultsKey)
    }

    func startNavigation(with waypoints: [Waypoint]) {
        guard !waypoints.isEmpty else {
            print("[NavigationManager] Error: Cannot start navigation with empty waypoints")
            return
        }

        self.waypoints = waypoints
        self.currentWaypointIndex = 0
        self.isNavigating = true
        self.distanceToNextWaypoint = 0
        self.nextInstructionText = ""
        self.nextInstructionDisplayText = ""
        self.activeManeuverAnnouncement = nil
        self.activeTurnManeuver = nil
        self.activeTurnTargetHeadingDegrees = nil

        // Show the first instruction (Start)
        let firstWaypoint = waypoints[0]
        self.currentBoardCommand = firstWaypoint.action.boardCommand == .arrived ? .arrived : .forward
        self.currentInstruction = firstWaypoint.action.instructionText
        print("[NavigationManager] Navigation started")
        print("[NavigationManager] Instruction: \(firstWaypoint.action.instructionText) at \(firstWaypoint.name)")
        print("[NavigationManager] Board command: \(currentBoardCommand.displayText)")

        // Move to next waypoint since we're starting from the first one
        if currentBoardCommand == .arrived {
            nextInstructionText = ""
            isNavigating = false
            print("[NavigationManager] Already at destination.")
        } else if waypoints.count > 1 {
            currentWaypointIndex = 1
            print("[NavigationManager] Now navigating to: \(waypoints[1].name)")
            syncSegmentStateForCurrentWaypoint()
        }
    }

    func stopNavigation() {
        isNavigating = false
        currentWaypointIndex = 0
        waypoints = []
        currentInstruction = ""
        nextInstructionText = ""
        nextInstructionDisplayText = ""
        currentBoardCommand = .idle
        activeManeuverAnnouncement = nil
        activeTurnManeuver = nil
        activeTurnTargetHeadingDegrees = nil
        clearAnnouncementWorkItem?.cancel()
        distanceToNextWaypoint = 0
        print("[NavigationManager] Navigation stopped")
    }

    // MARK: - Location Update Handler

    func updateLocation(_ location: CLLocation, headingDegrees: Double? = nil) {
        guard isNavigating, currentWaypointIndex < waypoints.count else { return }

        if handleActiveTurnProgress(location, headingDegrees: headingDegrees) {
            return
        }

        if let reachedWaypointIndex = reachedWaypointIndex(near: location) {
            if reachedWaypointIndex > currentWaypointIndex {
                print("[NavigationManager] Skipping to waypoint \(reachedWaypointIndex) to recover from missed intermediate checkpoints.")
                currentWaypointIndex = reachedWaypointIndex
            }

            let reachedWaypoint = waypoints[currentWaypointIndex]
            distanceToNextWaypoint = 0
            triggerInstruction(for: reachedWaypoint)
            if beginActiveTurnIfNeeded(for: reachedWaypoint, at: currentWaypointIndex) {
                return
            }
            advanceToNextWaypoint()
            return
        }

        let targetWaypoint = waypoints[currentWaypointIndex]
        let targetLocation = CLLocation(
            latitude: targetWaypoint.coordinate.latitude,
            longitude: targetWaypoint.coordinate.longitude
        )

        let distance = location.distance(from: targetLocation)
        distanceToNextWaypoint = distance
    }

    // MARK: - Private Helpers

    private func handleActiveTurnProgress(_ location: CLLocation, headingDegrees: Double?) -> Bool {
        guard let activeTurnManeuver else { return false }
        guard activeTurnManeuver.completionWaypointIndex < waypoints.count else {
            self.activeTurnManeuver = nil
            self.activeTurnTargetHeadingDegrees = nil
            return false
        }

        let completionWaypoint = waypoints[activeTurnManeuver.completionWaypointIndex]
        let completionLocation = CLLocation(
            latitude: completionWaypoint.coordinate.latitude,
            longitude: completionWaypoint.coordinate.longitude
        )
        let distanceToCompletionWaypoint = location.distance(from: completionLocation)
        distanceToNextWaypoint = distanceToCompletionWaypoint

        if shouldCompleteActiveTurn(
            activeTurnManeuver,
            at: location,
            headingDegrees: headingDegrees
        ) {
            let distanceFromTurn = location.distance(
                from: CLLocation(
                    latitude: activeTurnManeuver.triggerCoordinate.latitude,
                    longitude: activeTurnManeuver.triggerCoordinate.longitude
                )
            )
            if let expectedExitHeadingDegrees = activeTurnManeuver.expectedExitHeadingDegrees {
                let headingText: String
                if let headingDegrees {
                    let headingError = abs(Self.normalizedAngleDifference(headingDegrees - expectedExitHeadingDegrees))
                    headingText = String(
                        format: " heading %.1f deg (target %.1f deg, error %.1f deg)",
                        headingDegrees,
                        expectedExitHeadingDegrees,
                        headingError
                    )
                } else {
                    headingText = String(format: " target heading %.1f deg", expectedExitHeadingDegrees)
                }
                print(
                    String(
                        format: "[NavigationManager] Turn maneuver complete after %.1fm from trigger.%@",
                        distanceFromTurn,
                        headingText
                    )
                )
            } else {
                print(String(format: "[NavigationManager] Turn maneuver complete after %.1fm from trigger.", distanceFromTurn))
            }

            self.activeTurnManeuver = nil
            self.activeTurnTargetHeadingDegrees = nil
            syncSegmentStateForCurrentWaypoint()
            return false
        }

        currentBoardCommand = activeTurnManeuver.command
        currentInstruction = waypoints[activeTurnManeuver.triggerWaypointIndex].action.instructionText
        logActiveTurnProgress(
            activeTurnManeuver,
            at: location,
            headingDegrees: headingDegrees,
            distanceToCompletionWaypoint: distanceToCompletionWaypoint
        )
        return true
    }

    private func reachedWaypointIndex(near location: CLLocation) -> Int? {
        guard currentWaypointIndex < waypoints.count else { return nil }

        let upperBound = min(waypoints.count - 1, currentWaypointIndex + waypointLookaheadCount)
        var reachedIndices: [Int] = []

        for index in currentWaypointIndex...upperBound {
            let waypointLocation = CLLocation(
                latitude: waypoints[index].coordinate.latitude,
                longitude: waypoints[index].coordinate.longitude
            )

            if location.distance(from: waypointLocation) <= turnTriggerDistanceMeters {
                reachedIndices.append(index)
            }
        }

        guard !reachedIndices.isEmpty else { return nil }

        if let decisiveIndex = reachedIndices.last(where: { waypoints[$0].action != .straight }) {
            return decisiveIndex
        }

        return reachedIndices.last
    }

    private func triggerInstruction(for waypoint: Waypoint) {
        currentInstruction = waypoint.action.instructionText
        currentBoardCommand = waypoint.action.boardCommand
        publishManeuverAnnouncement(for: waypoint)

        // Print to console as requested
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("[NavigationManager] REACHED WAYPOINT: \(waypoint.name)")
        print("[NavigationManager] INSTRUCTION: \(waypoint.displayLabel)")
        print("[NavigationManager] Board command: \(currentBoardCommand.displayText)")
        if let maneuverNumber = waypoint.maneuverNumber {
            print("[NavigationManager] Maneuver ID: \(maneuverNumber)")
        }

        switch waypoint.action {
        case .start:
            print("[NavigationManager] → Begin your journey")
        case .left:
            print("[NavigationManager] ← Turn LEFT")
        case .right:
            print("[NavigationManager] → Turn RIGHT")
        case .straight:
            print("[NavigationManager] ↑ Go STRAIGHT through intersection")
        case .destination:
            print("[NavigationManager] ★ You have arrived at your DESTINATION!")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    private func beginActiveTurnIfNeeded(for waypoint: Waypoint, at waypointIndex: Int) -> Bool {
        guard (waypoint.action == .left || waypoint.action == .right),
              waypointIndex + 1 < waypoints.count else {
            return false
        }

        let completionWaypointIndex = waypointIndex + 1
        let completionWaypoint = waypoints[completionWaypointIndex]
        let expectedExitHeadingDegrees = Self.bearingDegrees(
            from: waypoint.coordinate,
            to: completionWaypoint.coordinate
        )

        activeTurnManeuver = ActiveTurnManeuver(
            triggerWaypointIndex: waypointIndex,
            completionWaypointIndex: completionWaypointIndex,
            command: waypoint.action.boardCommand,
            triggerCoordinate: waypoint.coordinate,
            expectedExitHeadingDegrees: expectedExitHeadingDegrees
        )
        activeTurnTargetHeadingDegrees = expectedExitHeadingDegrees
        currentWaypointIndex = completionWaypointIndex
        nextInstructionText = completionWaypoint.action.instructionText
        nextInstructionDisplayText = completionWaypoint.displayLabel
        currentInstruction = waypoint.action.instructionText
        currentBoardCommand = waypoint.action.boardCommand

        print(
            String(
                format: "[NavigationManager] Holding %@ until rider exits intersection and aligns with %.1f deg toward %@.",
                waypoint.action.boardCommand.displayText,
                expectedExitHeadingDegrees,
                completionWaypoint.name
            )
        )
        return true
    }

    private func advanceToNextWaypoint() {
        currentWaypointIndex += 1

        if currentWaypointIndex >= waypoints.count {
            currentBoardCommand = .arrived
            currentInstruction = NavigationAction.destination.instructionText
            nextInstructionText = ""
            nextInstructionDisplayText = ""
            print("[NavigationManager] Navigation complete - all waypoints reached!")
            isNavigating = false
        } else {
            let nextWaypoint = waypoints[currentWaypointIndex]
            print("[NavigationManager] Now navigating to: \(nextWaypoint.name)")
            syncSegmentStateForCurrentWaypoint()
        }
    }

    private func syncSegmentStateForCurrentWaypoint() {
        guard isNavigating, currentWaypointIndex < waypoints.count else {
            nextInstructionText = ""
            nextInstructionDisplayText = ""
            return
        }

        let nextWaypoint = waypoints[currentWaypointIndex]
        currentBoardCommand = .forward
        currentInstruction = nextWaypoint.action.instructionText
        nextInstructionText = nextWaypoint.action.instructionText
        nextInstructionDisplayText = nextWaypoint.displayLabel
        print("[NavigationManager] Segment command: \(currentBoardCommand.displayText). Next instruction: \(nextInstructionDisplayText) at \(nextWaypoint.name)")
    }

    private func publishManeuverAnnouncement(for waypoint: Waypoint) {
        clearAnnouncementWorkItem?.cancel()
        activeManeuverAnnouncement = nil

        guard waypoint.action != .start, waypoint.action != .destination else { return }

        let announcement = NavigationManeuverAnnouncement(
            command: waypoint.action.boardCommand,
            title: waypoint.displayLabel,
            subtitle: "Triggered at \(waypoint.name)",
            maneuverNumber: waypoint.maneuverNumber
        )
        activeManeuverAnnouncement = announcement

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.activeManeuverAnnouncement = nil
        }
        clearAnnouncementWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + maneuverAnnouncementDuration,
            execute: workItem
        )
    }

    private func shouldCompleteActiveTurn(
        _ activeTurnManeuver: ActiveTurnManeuver,
        at location: CLLocation,
        headingDegrees: Double?
    ) -> Bool {
        let triggerLocation = CLLocation(
            latitude: activeTurnManeuver.triggerCoordinate.latitude,
            longitude: activeTurnManeuver.triggerCoordinate.longitude
        )
        let distanceFromTrigger = location.distance(from: triggerLocation)
        let minimumTravel = max(
            minimumTurnCompletionTravelMeters,
            min(turnTriggerDistanceMeters * 0.35, 8.0)
        )

        guard distanceFromTrigger >= minimumTravel else {
            return false
        }

        guard let headingDegrees,
              let expectedExitHeadingDegrees = activeTurnManeuver.expectedExitHeadingDegrees else {
            return false
        }

        let headingError = abs(Self.normalizedAngleDifference(headingDegrees - expectedExitHeadingDegrees))
        return headingError <= turnCompletionHeadingToleranceDegrees
    }

    private func logActiveTurnProgress(
        _ activeTurnManeuver: ActiveTurnManeuver,
        at location: CLLocation,
        headingDegrees: Double?,
        distanceToCompletionWaypoint: CLLocationDistance
    ) {
        let distanceFromTrigger = CLLocation(
            latitude: activeTurnManeuver.triggerCoordinate.latitude,
            longitude: activeTurnManeuver.triggerCoordinate.longitude
        ).distance(from: location)
        let minimumTravel = max(
            minimumTurnCompletionTravelMeters,
            min(turnTriggerDistanceMeters * 0.35, 8.0)
        )
        let hasMinimumTravel = distanceFromTrigger >= minimumTravel

        if let headingDegrees, let expectedExitHeadingDegrees = activeTurnManeuver.expectedExitHeadingDegrees {
            let headingError = abs(Self.normalizedAngleDifference(headingDegrees - expectedExitHeadingDegrees))
            print(
                String(
                    format: "[NavigationManager] Turn in progress: %@, rider heading %.1f deg, target %.1f deg, error %.1f deg, distance-from-trigger %.1fm, min-travel %@, distance-to-exit %.1fm",
                    activeTurnManeuver.command.displayText,
                    headingDegrees,
                    expectedExitHeadingDegrees,
                    headingError,
                    distanceFromTrigger,
                    hasMinimumTravel ? "yes" : "no",
                    distanceToCompletionWaypoint
                )
            )
        } else {
            print(
                String(
                    format: "[NavigationManager] Turn in progress: %@, heading unavailable, distance-from-trigger %.1fm, min-travel %@, distance-to-exit %.1fm",
                    activeTurnManeuver.command.displayText,
                    distanceFromTrigger,
                    hasMinimumTravel ? "yes" : "no",
                    distanceToCompletionWaypoint
                )
            )
        }
    }

    private static func clampedTurnTriggerDistance(_ value: CLLocationDistance) -> CLLocationDistance {
        min(max(value, minimumTurnTriggerDistanceMeters), maximumTurnTriggerDistanceMeters)
    }

    private static func bearingDegrees(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180

        let y = sin(deltaLongitude) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude) -
            sin(startLatitude) * cos(endLatitude) * cos(deltaLongitude)

        let bearing = atan2(y, x) * 180 / .pi
        return bearing >= 0 ? bearing : bearing + 360
    }

    private static func normalizedAngleDifference(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized > 180 {
            normalized -= 360
        } else if normalized < -180 {
            normalized += 360
        }
        return normalized
    }
}
