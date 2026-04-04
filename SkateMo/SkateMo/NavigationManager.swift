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

class NavigationManager: ObservableObject {

    // Epsilon distance in meters - when user is within this distance of waypoint, trigger instruction
    let epsilon: CLLocationDistance = 15.0  // 15 meters
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

    // Distance to next waypoint
    @Published var distanceToNextWaypoint: CLLocationDistance = 0

    private let maneuverAnnouncementDuration: TimeInterval = 1.75
    private var clearAnnouncementWorkItem: DispatchWorkItem?

    // MARK: - Navigation Control

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
        clearAnnouncementWorkItem?.cancel()
        distanceToNextWaypoint = 0
        print("[NavigationManager] Navigation stopped")
    }

    // MARK: - Location Update Handler

    func updateLocation(_ location: CLLocation) {
        guard isNavigating, currentWaypointIndex < waypoints.count else { return }

        if let reachedWaypointIndex = reachedWaypointIndex(near: location) {
            if reachedWaypointIndex > currentWaypointIndex {
                print("[NavigationManager] Skipping to waypoint \(reachedWaypointIndex) to recover from missed intermediate checkpoints.")
                currentWaypointIndex = reachedWaypointIndex
            }

            let reachedWaypoint = waypoints[currentWaypointIndex]
            distanceToNextWaypoint = 0
            triggerInstruction(for: reachedWaypoint)
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

    private func reachedWaypointIndex(near location: CLLocation) -> Int? {
        guard currentWaypointIndex < waypoints.count else { return nil }

        let upperBound = min(waypoints.count - 1, currentWaypointIndex + waypointLookaheadCount)
        var reachedIndices: [Int] = []

        for index in currentWaypointIndex...upperBound {
            let waypointLocation = CLLocation(
                latitude: waypoints[index].coordinate.latitude,
                longitude: waypoints[index].coordinate.longitude
            )

            if location.distance(from: waypointLocation) <= epsilon {
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
}
