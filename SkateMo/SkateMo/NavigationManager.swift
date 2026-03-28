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
}

class NavigationManager: ObservableObject {

    // Epsilon distance in meters - when user is within this distance of waypoint, trigger instruction
    let epsilon: CLLocationDistance = 15.0  // 15 meters

    // The route waypoints with instructions
    @Published var waypoints: [Waypoint] = []

    // Current waypoint index (the one we're navigating towards)
    @Published var currentWaypointIndex: Int = 0

    // Whether navigation is active
    @Published var isNavigating: Bool = false

    // Current instruction to display
    @Published var currentInstruction: String = ""
    @Published var currentBoardCommand: BoardCommand = .idle

    // Distance to next waypoint
    @Published var distanceToNextWaypoint: CLLocationDistance = 0

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
        self.currentBoardCommand = .forward

        // Show the first instruction (Start)
        let firstWaypoint = waypoints[0]
        self.currentInstruction = firstWaypoint.action.instructionText
        print("[NavigationManager] Navigation started")
        print("[NavigationManager] Instruction: \(firstWaypoint.action.instructionText) at \(firstWaypoint.name)")
        print("[NavigationManager] Board command: \(currentBoardCommand.displayText)")

        // Move to next waypoint since we're starting from the first one
        if waypoints.count > 1 {
            currentWaypointIndex = 1
            print("[NavigationManager] Now navigating to: \(waypoints[1].name)")
        }
    }

    func stopNavigation() {
        isNavigating = false
        currentWaypointIndex = 0
        waypoints = []
        currentInstruction = ""
        currentBoardCommand = .idle
        distanceToNextWaypoint = 0
        print("[NavigationManager] Navigation stopped")
    }

    // MARK: - Location Update Handler

    func updateLocation(_ location: CLLocation) {
        guard isNavigating, currentWaypointIndex < waypoints.count else { return }

        let targetWaypoint = waypoints[currentWaypointIndex]
        let targetLocation = CLLocation(
            latitude: targetWaypoint.coordinate.latitude,
            longitude: targetWaypoint.coordinate.longitude
        )

        let distance = location.distance(from: targetLocation)
        distanceToNextWaypoint = distance

        // Check if within epsilon proximity
        if distance <= epsilon {
            triggerInstruction(for: targetWaypoint)
            advanceToNextWaypoint()
        }
    }

    // MARK: - Private Helpers

    private func triggerInstruction(for waypoint: Waypoint) {
        currentInstruction = waypoint.action.instructionText
        currentBoardCommand = waypoint.action.boardCommand

        // Print to console as requested
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("[NavigationManager] REACHED WAYPOINT: \(waypoint.name)")
        print("[NavigationManager] INSTRUCTION: \(waypoint.action.instructionText)")
        print("[NavigationManager] Board command: \(currentBoardCommand.displayText)")

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
            print("[NavigationManager] Navigation complete - all waypoints reached!")
            isNavigating = false
        } else {
            let nextWaypoint = waypoints[currentWaypointIndex]
            print("[NavigationManager] Now navigating to: \(nextWaypoint.name)")
        }
    }
}
