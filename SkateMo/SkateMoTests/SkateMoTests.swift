//
//  SkateMoTests.swift
//  SkateMoTests
//
//  Created by Justin Jiang on 11/24/25.
//

import Testing
import CoreLocation
@testable import SkateMo

struct SkateMoTests {

    @Test func rideSupervisorPrefersNavigationWhenPathIsClear() {
        let resolved = RideSessionManager.resolveCommand(
            rideActive: true,
            navigationCommand: .forward,
            obstacleState: .go,
            previousLastNavigationCommand: .idle
        )

        #expect(resolved.effectiveCommand == .forward)
        #expect(resolved.source == .navigation)
    }

    @Test func rideSupervisorStopsForVisionOverride() {
        let resolved = RideSessionManager.resolveCommand(
            rideActive: true,
            navigationCommand: .forward,
            obstacleState: .stop,
            previousLastNavigationCommand: .forward
        )

        #expect(resolved.effectiveCommand == .stopForObstacle)
        #expect(resolved.source == .vision)
    }

    @Test func rideSupervisorKeepsArrivedAboveVisionStop() {
        let resolved = RideSessionManager.resolveCommand(
            rideActive: true,
            navigationCommand: .arrived,
            obstacleState: .stop,
            previousLastNavigationCommand: .forward
        )

        #expect(resolved.effectiveCommand == .arrived)
        #expect(resolved.source == .system)
    }

    @Test func rideSupervisorResumesPreviousNavigationCommandAfterClear() {
        let stopped = RideSessionManager.resolveCommand(
            rideActive: true,
            navigationCommand: .turnRight,
            obstacleState: .stop,
            previousLastNavigationCommand: .forward
        )

        let resumed = RideSessionManager.resolveCommand(
            rideActive: true,
            navigationCommand: .turnRight,
            obstacleState: .go,
            previousLastNavigationCommand: stopped.cachedNavigationCommand
        )

        #expect(stopped.effectiveCommand == .stopForObstacle)
        #expect(resumed.effectiveCommand == .turnRight)
        #expect(resumed.source == .navigation)
    }

    @Test func navigationManagerStartsWithForwardCommand() {
        let manager = NavigationManager()

        manager.startNavigation(with: sampleWaypoints())

        #expect(manager.currentBoardCommand == .forward)
        #expect(manager.currentInstruction == NavigationAction.start.instructionText)
    }

    @Test func navigationManagerPublishesTurnCommandAtWaypoint() {
        let manager = NavigationManager()

        manager.startNavigation(with: sampleWaypoints())
        manager.updateLocation(CLLocation(latitude: 34.0195, longitude: -118.2879))

        #expect(manager.currentBoardCommand == .turnRight)
        #expect(manager.currentInstruction == NavigationAction.right.instructionText)
    }

    @Test func navigationManagerPublishesArrivedAtDestination() {
        let manager = NavigationManager()

        manager.startNavigation(with: sampleWaypoints())
        manager.updateLocation(CLLocation(latitude: 34.0195, longitude: -118.2879))
        manager.updateLocation(CLLocation(latitude: 34.0185, longitude: -118.2879))

        #expect(manager.currentBoardCommand == .arrived)
        #expect(manager.currentInstruction == NavigationAction.destination.instructionText)
        #expect(manager.isNavigating == false)
    }

    private func sampleWaypoints() -> [Waypoint] {
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
                coordinate: CLLocationCoordinate2D(latitude: 34.0185, longitude: -118.2879),
                action: .destination
            )
        ]
    }

}
