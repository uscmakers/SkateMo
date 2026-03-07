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
    let instruction: String  // "Start", "Left", "Right", "Intersection", "Destination"
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

        // Show the first instruction (Start)
        let firstWaypoint = waypoints[0]
        self.currentInstruction = firstWaypoint.instruction
        print("[NavigationManager] Navigation started")
        print("[NavigationManager] Instruction: \(firstWaypoint.instruction) at \(firstWaypoint.name)")

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
        currentInstruction = waypoint.instruction

        // Print to console as requested
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("[NavigationManager] REACHED WAYPOINT: \(waypoint.name)")
        print("[NavigationManager] INSTRUCTION: \(waypoint.instruction)")

        switch waypoint.instruction {
        case "Start":
            print("[NavigationManager] → Begin your journey")
        case "Left":
            print("[NavigationManager] ← Turn LEFT")
        case "Right":
            print("[NavigationManager] → Turn RIGHT")
        case "Intersection":
            print("[NavigationManager] ↑ Go STRAIGHT through intersection")
        case "Destination":
            print("[NavigationManager] ★ You have arrived at your DESTINATION!")
        default:
            print("[NavigationManager] Continue on path")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    private func advanceToNextWaypoint() {
        currentWaypointIndex += 1

        if currentWaypointIndex >= waypoints.count {
            print("[NavigationManager] Navigation complete - all waypoints reached!")
            isNavigating = false
        } else {
            let nextWaypoint = waypoints[currentWaypointIndex]
            print("[NavigationManager] Now navigating to: \(nextWaypoint.name)")
        }
    }
}
