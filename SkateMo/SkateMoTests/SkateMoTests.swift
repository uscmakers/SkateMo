//
//  SkateMoTests.swift
//  SkateMoTests
//
//  Created by Justin Jiang on 11/24/25.
//

import Testing
import CoreLocation
import Foundation
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
        #expect(manager.currentInstruction == NavigationAction.right.instructionText)
        #expect(manager.nextInstructionText == NavigationAction.right.instructionText)
        #expect(manager.nextInstructionDisplayText == "TURN 1: RIGHT")
    }

    @Test func navigationManagerReturnsToForwardAfterTurnWaypoint() {
        let manager = NavigationManager()

        manager.startNavigation(with: sampleWaypoints())
        manager.updateLocation(CLLocation(latitude: 34.0195, longitude: -118.2879))

        #expect(manager.currentBoardCommand == .forward)
        #expect(manager.currentInstruction == NavigationAction.destination.instructionText)
        #expect(manager.nextInstructionText == NavigationAction.destination.instructionText)
        #expect(manager.activeManeuverAnnouncement?.title == "TURN 1: RIGHT")
        #expect(manager.activeManeuverAnnouncement?.maneuverNumber == 1)
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

    @Test func navigationManagerRecoversIfIntermediateStraightWaypointIsMissed() {
        let manager = NavigationManager()

        manager.startNavigation(with: [
            Waypoint(
                name: "Start Point",
                coordinate: CLLocationCoordinate2D(latitude: 34.0000, longitude: -118.0000),
                action: .start
            ),
            Waypoint(
                name: "Straight Checkpoint",
                coordinate: CLLocationCoordinate2D(latitude: 34.0000, longitude: -117.9995),
                action: .straight
            ),
            Waypoint(
                name: "Turn Right",
                coordinate: CLLocationCoordinate2D(latitude: 34.0000, longitude: -117.9990),
                action: .right,
                maneuverNumber: 1
            ),
            Waypoint(
                name: "Destination",
                coordinate: CLLocationCoordinate2D(latitude: 34.0010, longitude: -117.9990),
                action: .destination
            )
        ])

        manager.updateLocation(CLLocation(latitude: 34.0000, longitude: -117.9990))

        #expect(manager.currentBoardCommand == .forward)
        #expect(manager.currentInstruction == NavigationAction.destination.instructionText)
        #expect(manager.nextInstructionText == NavigationAction.destination.instructionText)
        #expect(manager.activeManeuverAnnouncement?.title == "TURN 1: RIGHT")
        #expect(manager.currentWaypointIndex == 3)
    }

    @Test func navigationManagerKeepsForwardBetweenSequentialTurnWaypoints() {
        let manager = NavigationManager()

        manager.startNavigation(with: [
            Waypoint(
                name: "Start Point",
                coordinate: CLLocationCoordinate2D(latitude: 34.0000, longitude: -118.0000),
                action: .start
            ),
            Waypoint(
                name: "First Right",
                coordinate: CLLocationCoordinate2D(latitude: 34.0000, longitude: -117.9990),
                action: .right,
                maneuverNumber: 1
            ),
            Waypoint(
                name: "Second Right",
                coordinate: CLLocationCoordinate2D(latitude: 34.0010, longitude: -117.9990),
                action: .right,
                maneuverNumber: 2
            ),
            Waypoint(
                name: "Destination",
                coordinate: CLLocationCoordinate2D(latitude: 34.0010, longitude: -117.9980),
                action: .destination
            )
        ])

        manager.updateLocation(CLLocation(latitude: 34.0000, longitude: -117.9990))

        #expect(manager.currentBoardCommand == .forward)
        #expect(manager.currentInstruction == NavigationAction.right.instructionText)
        #expect(manager.nextInstructionText == NavigationAction.right.instructionText)
        #expect(manager.nextInstructionDisplayText == "TURN 2: RIGHT")
        #expect(manager.activeManeuverAnnouncement?.title == "TURN 1: RIGHT")
        #expect(manager.currentWaypointIndex == 2)
    }

    @Test func rideSupervisorResumesForwardBetweenTurnWaypointsAfterClear() {
        let stopped = RideSessionManager.resolveCommand(
            rideActive: true,
            navigationCommand: .forward,
            obstacleState: .stop,
            previousLastNavigationCommand: .turnRight
        )

        let resumed = RideSessionManager.resolveCommand(
            rideActive: true,
            navigationCommand: .forward,
            obstacleState: .go,
            previousLastNavigationCommand: stopped.cachedNavigationCommand
        )

        #expect(stopped.effectiveCommand == .stopForObstacle)
        #expect(resumed.effectiveCommand == .forward)
        #expect(resumed.source == .navigation)
    }

    @Test func campusRoutePlannerKeepsOnlyTurnWaypointsForNavigation() throws {
        let csv = """
        start_lat,start_lon,end_lat,end_lon,road_name,road_type,distance_ft
        34.0000,-118.0000,34.0000,-117.9990,Main,,100
        34.0000,-117.9990,34.0000,-117.9980,Main,,100
        34.0000,-117.9980,34.0010,-117.9980,Cross,,100
        """
        let csvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)

        let planner = try CampusRoutePlanner(csvURL: csvURL)
        let route = try planner.route(
            from: CLLocationCoordinate2D(latitude: 34.0000, longitude: -118.0000),
            to: CLLocationCoordinate2D(latitude: 34.0010, longitude: -117.9980)
        )

        #expect(route.coordinates.count == 4)
        #expect(route.waypoints.map(\.action) == [.start, .right, .destination])
        #expect(route.waypoints[1].maneuverNumber == 1)
    }

    @Test func campusRoutePlannerDeduplicatesEdgesAndDropsSteps() throws {
        let planner = try planner(
            """
            start_lat,start_lon,end_lat,end_lon,road_name,road_type,distance_ft
            34.0000,-118.0000,34.0000,-117.9990,Main,service,100
            34.0000,-117.9990,34.0000,-118.0000,Main,service,100
            34.0000,-117.9990,34.0010,-117.9990,Stairs,"footway, steps",50
            34.0010,-117.9990,34.0020,-117.9990,Path,footway,90
            """
        )

        #expect(planner.debugUniqueEdgeCount == 2)
    }

    @Test func campusRoutePlannerPrefersServiceRoadsOverUnnamedFootways() throws {
        let planner = try planner(
            """
            start_lat,start_lon,end_lat,end_lon,road_name,road_type,distance_ft
            34.0000,-118.0020,34.0000,-118.0010,Main,service,100
            34.0000,-118.0010,34.0000,-118.0000,Main,service,100
            34.0000,-118.0020,34.0010,-118.0010,Unnamed,footway,100
            34.0010,-118.0010,34.0000,-118.0000,Unnamed,footway,100
            """
        )

        let route = try planner.route(
            from: CLLocationCoordinate2D(latitude: 34.0000, longitude: -118.0020),
            to: CLLocationCoordinate2D(latitude: 34.0000, longitude: -118.0000)
        )

        #expect(route.startEdgeRoadName == "Main")
        #expect(route.coordinates.contains { coordinate in
            approximatelyEqual(
                coordinate,
                CLLocationCoordinate2D(latitude: 34.0000, longitude: -118.0010)
            )
        })
        #expect(!route.coordinates.contains { coordinate in
            approximatelyEqual(
                coordinate,
                CLLocationCoordinate2D(latitude: 34.0010, longitude: -118.0010)
            )
        })
    }

    @Test func campusRoutePlannerProjectsMidBlockStartsOntoEdge() throws {
        let planner = try planner(
            """
            start_lat,start_lon,end_lat,end_lon,road_name,road_type,distance_ft
            34.0000,-118.0020,34.0000,-118.0010,Main,service,100
            34.0000,-118.0010,34.0000,-118.0000,Main,service,100
            """
        )

        let route = try planner.route(
            from: CLLocationCoordinate2D(latitude: 34.0001, longitude: -118.0015),
            to: CLLocationCoordinate2D(latitude: 34.0000, longitude: -118.0000)
        )

        #expect(route.startDistanceMeters < 15)
        #expect(route.coordinates.first!.longitude > -118.0020)
        #expect(route.coordinates.first!.longitude < -118.0010)
    }

    @Test func campusRoutePlannerUsesHeadingBiasForFirstSegment() throws {
        let planner = try planner(
            """
            start_lat,start_lon,end_lat,end_lon,road_name,road_type,distance_ft
            34.0000,-118.0020,34.0000,-118.0000,Main,service,100
            34.0000,-118.0020,34.0010,-118.0010,Northwest,service,100
            34.0000,-118.0000,34.0010,-118.0010,Northeast,service,100
            """
        )

        let route = try planner.route(
            from: CLLocationCoordinate2D(latitude: 34.0000, longitude: -118.0010),
            to: CLLocationCoordinate2D(latitude: 34.0010, longitude: -118.0010),
            travelHeadingDegrees: 270
        )

        #expect(route.firstSegmentBearingDegrees != nil)
        #expect(abs(angleDifference(route.firstSegmentBearingDegrees!, 270)) < 30)
    }

    @Test func campusRoutePlannerSuppressesImmediateSameRoadTurn() throws {
        let planner = try planner(
            """
            start_lat,start_lon,end_lat,end_lon,road_name,road_type,distance_ft
            34.0000,-118.0020,34.0000,-118.0017,Main,service,30
            34.0000,-118.0017,33.9997,-118.0017,Main,service,30
            33.9997,-118.0017,33.9987,-118.0017,Main,service,100
            """
        )

        let route = try planner.route(
            from: CLLocationCoordinate2D(latitude: 34.0000, longitude: -118.0020),
            to: CLLocationCoordinate2D(latitude: 33.9987, longitude: -118.0017)
        )

        #expect(!route.waypoints.contains(where: { waypoint in
            waypoint.action == .left || waypoint.action == .right
        }))
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
                action: .right,
                maneuverNumber: 1
            ),
            Waypoint(
                name: "Destination",
                coordinate: CLLocationCoordinate2D(latitude: 34.0185, longitude: -118.2879),
                action: .destination
            )
        ]
    }

    private func planner(_ csv: String) throws -> CampusRoutePlanner {
        let csvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)
        return try CampusRoutePlanner(csvURL: csvURL)
    }

    private func approximatelyEqual(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)) < 1.0
    }

    private func angleDifference(_ lhs: Double, _ rhs: Double) -> Double {
        var difference = lhs - rhs
        while difference > 180 {
            difference -= 360
        }
        while difference < -180 {
            difference += 360
        }
        return difference
    }

}
