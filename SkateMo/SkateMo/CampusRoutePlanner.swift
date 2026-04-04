//
//  CampusRoutePlanner.swift
//  SkateMo
//

import CoreLocation
import Foundation

struct PlannedRoute {
    let waypoints: [Waypoint]
    let coordinates: [CLLocationCoordinate2D]
    let totalDistanceFeet: Double
    let weightedDistanceFeet: Double
    let startDistanceMeters: Double
    let endDistanceMeters: Double
    let startEdgeRoadName: String
    let startEdgeHighwayTypes: [String]
    let endEdgeRoadName: String
    let endEdgeHighwayTypes: [String]
    let firstSegmentBearingDegrees: Double?
    let maneuverDebugDescriptions: [String]

    var navigationStepCount: Int {
        max(waypoints.count - 1, 0)
    }
}

enum RoutePlanningError: LocalizedError {
    case graphUnavailable
    case invalidGraphData
    case startTooFar(Double)
    case destinationTooFar(Double)
    case noPathFound

    var errorDescription: String? {
        switch self {
        case .graphUnavailable:
            return "The USC route graph is not available in the app bundle."
        case .invalidGraphData:
            return "The USC route graph data could not be parsed."
        case .startTooFar(let meters):
            return String(format: "Current location is %.0fm from the nearest skateboard route.", meters)
        case .destinationTooFar(let meters):
            return String(format: "Destination is %.0fm from the nearest skateboard route.", meters)
        case .noPathFound:
            return "No campus route was found between the selected points."
        }
    }
}

final class CampusRoutePlanner {
    private struct GraphNode: Hashable, Comparable {
        let latitude: Double
        let longitude: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        static func < (lhs: GraphNode, rhs: GraphNode) -> Bool {
            if lhs.latitude == rhs.latitude {
                return lhs.longitude < rhs.longitude
            }
            return lhs.latitude < rhs.latitude
        }
    }

    private struct GraphEdgeKey: Hashable {
        let first: GraphNode
        let second: GraphNode

        init(_ nodeA: GraphNode, _ nodeB: GraphNode) {
            if nodeA <= nodeB {
                first = nodeA
                second = nodeB
            } else {
                first = nodeB
                second = nodeA
            }
        }
    }

    private struct GraphEdge {
        let key: GraphEdgeKey
        let nodeA: GraphNode
        let nodeB: GraphNode
        let roadName: String
        let normalizedRoadName: String
        let highwayTypes: [String]
        let displayName: String
        let distanceFeet: Double
        let weightedDistanceFeet: Double

        var roadFamily: String {
            Self.roadFamily(for: normalizedRoadName, highwayTypes: highwayTypes)
        }

        var isGeometrySegment: Bool {
            normalizedRoadName == "unnamed" && (highwayTypes.contains("service") || highwayTypes.contains("pedestrian"))
        }

        func otherNode(from node: GraphNode) -> GraphNode {
            node == nodeA ? nodeB : nodeA
        }

        static func roadFamily(for normalizedRoadName: String, highwayTypes: [String]) -> String {
            if normalizedRoadName != "unnamed" {
                return "road:\(normalizedRoadName)"
            }
            if highwayTypes.contains("service") || highwayTypes.contains("pedestrian") {
                return "geometry"
            }
            return "unnamed-footway"
        }
    }

    private struct EdgeProjectionCandidate {
        let edge: GraphEdge
        let projectedCoordinate: CLLocationCoordinate2D
        let fractionAlongEdge: Double
        let distanceMeters: Double
    }

    private enum RouterNode: Hashable {
        case graph(GraphNode)
        case start
        case end
    }

    private struct RouteNeighbor {
        let node: RouterNode
        let rawDistanceFeet: Double
        let weightedDistanceFeet: Double
        let roadName: String
        let normalizedRoadName: String
        let highwayTypes: [String]
        let displayName: String
        let startCoordinate: CLLocationCoordinate2D
        let endCoordinate: CLLocationCoordinate2D
    }

    private struct RoutedSegment {
        let startCoordinate: CLLocationCoordinate2D
        let endCoordinate: CLLocationCoordinate2D
        let roadName: String
        let normalizedRoadName: String
        let highwayTypes: [String]
        let displayName: String
        let roadFamily: String
        let isGeometrySegment: Bool
        let distanceFeet: Double
        let weightedDistanceFeet: Double
        let bearingDegrees: Double
    }

    private enum TurnClassification {
        case straight
        case left
        case right
        case uTurnLeft
        case uTurnRight

        var isUTurn: Bool {
            switch self {
            case .uTurnLeft, .uTurnRight:
                return true
            case .straight, .left, .right:
                return false
            }
        }

        var navigationAction: NavigationAction {
            switch self {
            case .straight:
                return .straight
            case .left, .uTurnLeft:
                return .left
            case .right, .uTurnRight:
                return .right
            }
        }
    }

    private struct NavigationBuildResult {
        let waypoints: [Waypoint]
        let maneuverDescriptions: [String]
        let firstManeuverIsUTurn: Bool
    }

    private struct CandidateRoute {
        let segments: [RoutedSegment]
        let coordinates: [CLLocationCoordinate2D]
        let waypoints: [Waypoint]
        let rawDistanceFeet: Double
        let weightedDistanceFeet: Double
        let scoreFeet: Double
        let startCandidate: EdgeProjectionCandidate
        let endCandidate: EdgeProjectionCandidate
        let firstSegmentBearingDegrees: Double?
        let maneuverDescriptions: [String]
    }

    private struct CSVHeaderMapping {
        let lat1: Int
        let lon1: Int
        let lat2: Int
        let lon2: Int
        let roadName: Int
        let highwayTypes: Int
        let distanceFeet: Int
    }

    private let adjacency: [GraphNode: [GraphEdge]]
    private let edges: [GraphEdge]
    private let nodes: [GraphNode]

    private let candidateSnapThresholdMeters = 25.0
    private let startCandidateLimit = 5
    private let endCandidateLimit = 3
    private let shortInitialTurnSuppressionFeet = 60.0
    private let minimumDistanceBetweenInstructionsFeet = 45.0

    var debugUniqueEdgeCount: Int {
        edges.count
    }

    convenience init() throws {
        guard let csvURL = Bundle.main.url(forResource: "usc_campus_internal_edges", withExtension: "csv") else {
            throw RoutePlanningError.graphUnavailable
        }
        try self.init(csvURL: csvURL)
    }

    init(csvURL: URL) throws {
        let contents = try String(contentsOf: csvURL, encoding: .utf8)
        let rows = Self.parseCSV(contents)

        guard let headerRow = rows.first,
              let headerMapping = Self.headerMapping(for: headerRow) else {
            throw RoutePlanningError.invalidGraphData
        }

        var deduplicatedEdges: [GraphEdgeKey: GraphEdge] = [:]

        for row in rows.dropFirst() {
            guard let parsed = Self.parseRow(row, mapping: headerMapping) else { continue }

            let nodeA = GraphNode(latitude: parsed.lat1, longitude: parsed.lon1)
            let nodeB = GraphNode(latitude: parsed.lat2, longitude: parsed.lon2)
            let roadName = Self.cleanedRoadName(parsed.roadName)
            let highwayTypes = Self.normalizedHighwayTypes(parsed.highwayTypes)

            guard !highwayTypes.contains("steps") else { continue }

            let edge = Self.makeEdge(
                nodeA: nodeA,
                nodeB: nodeB,
                roadName: roadName,
                highwayTypes: highwayTypes,
                distanceFeet: parsed.distanceFeet
            )

            if let existing = deduplicatedEdges[edge.key] {
                deduplicatedEdges[edge.key] = Self.merge(existing, with: edge)
            } else {
                deduplicatedEdges[edge.key] = edge
            }
        }

        guard !deduplicatedEdges.isEmpty else {
            throw RoutePlanningError.invalidGraphData
        }

        let edges = Array(deduplicatedEdges.values)
        var adjacency: [GraphNode: [GraphEdge]] = [:]

        for edge in edges {
            adjacency[edge.nodeA, default: []].append(edge)
            adjacency[edge.nodeB, default: []].append(edge)
        }

        self.edges = edges
        self.adjacency = adjacency
        self.nodes = Array(adjacency.keys)
    }

    func route(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        travelHeadingDegrees: Double? = nil
    ) throws -> PlannedRoute {
        let startCandidates = edgeCandidates(near: start, limit: startCandidateLimit)
        let endCandidates = edgeCandidates(near: destination, limit: endCandidateLimit)

        guard !startCandidates.isEmpty else {
            throw RoutePlanningError.startTooFar(nearestEdgeDistance(to: start) ?? candidateSnapThresholdMeters)
        }
        guard !endCandidates.isEmpty else {
            throw RoutePlanningError.destinationTooFar(nearestEdgeDistance(to: destination) ?? candidateSnapThresholdMeters)
        }

        let startHeading = Self.normalizedHeading(travelHeadingDegrees)
        var bestRoute: CandidateRoute?

        for startCandidate in startCandidates {
            for endCandidate in endCandidates {
                guard let candidate = buildCandidateRoute(
                    start: startCandidate,
                    end: endCandidate,
                    travelHeadingDegrees: startHeading
                ) else {
                    continue
                }

                if let currentBest = bestRoute {
                    if candidate.scoreFeet < currentBest.scoreFeet ||
                        (candidate.scoreFeet == currentBest.scoreFeet && candidate.rawDistanceFeet < currentBest.rawDistanceFeet) {
                        bestRoute = candidate
                    }
                } else {
                    bestRoute = candidate
                }
            }
        }

        guard let bestRoute else {
            throw RoutePlanningError.noPathFound
        }

        return PlannedRoute(
            waypoints: bestRoute.waypoints,
            coordinates: bestRoute.coordinates,
            totalDistanceFeet: bestRoute.rawDistanceFeet,
            weightedDistanceFeet: bestRoute.weightedDistanceFeet,
            startDistanceMeters: bestRoute.startCandidate.distanceMeters,
            endDistanceMeters: bestRoute.endCandidate.distanceMeters,
            startEdgeRoadName: bestRoute.startCandidate.edge.roadName,
            startEdgeHighwayTypes: bestRoute.startCandidate.edge.highwayTypes,
            endEdgeRoadName: bestRoute.endCandidate.edge.roadName,
            endEdgeHighwayTypes: bestRoute.endCandidate.edge.highwayTypes,
            firstSegmentBearingDegrees: bestRoute.firstSegmentBearingDegrees,
            maneuverDebugDescriptions: bestRoute.maneuverDescriptions
        )
    }

    private func buildCandidateRoute(
        start: EdgeProjectionCandidate,
        end: EdgeProjectionCandidate,
        travelHeadingDegrees: Double?
    ) -> CandidateRoute? {
        guard let segments = shortestPathSegments(from: start, to: end) else {
            return nil
        }

        let coordinates = Self.routeCoordinates(from: segments)
        let rawDistanceFeet = segments.reduce(0.0) { $0 + $1.distanceFeet }
        let weightedDistanceFeet = segments.reduce(0.0) { $0 + $1.weightedDistanceFeet }
        let navigation = buildNavigationWaypoints(
            from: segments,
            startDisplayName: start.edge.displayName,
            destinationDisplayName: end.edge.displayName
        )

        guard !navigation.firstManeuverIsUTurn else {
            return nil
        }

        let firstSegmentBearingDegrees = segments.first(where: { $0.distanceFeet > 1.0 })?.bearingDegrees
        let headingPenaltyFeet = headingPenalty(
            firstSegmentBearingDegrees: firstSegmentBearingDegrees,
            travelHeadingDegrees: travelHeadingDegrees
        )
        let snapPenaltyFeet = (start.distanceMeters + end.distanceMeters) * 3.28084
        let scoreFeet = weightedDistanceFeet + snapPenaltyFeet + headingPenaltyFeet

        return CandidateRoute(
            segments: segments,
            coordinates: coordinates,
            waypoints: navigation.waypoints,
            rawDistanceFeet: rawDistanceFeet,
            weightedDistanceFeet: weightedDistanceFeet,
            scoreFeet: scoreFeet,
            startCandidate: start,
            endCandidate: end,
            firstSegmentBearingDegrees: firstSegmentBearingDegrees,
            maneuverDescriptions: navigation.maneuverDescriptions
        )
    }

    private func shortestPathSegments(
        from startCandidate: EdgeProjectionCandidate,
        to endCandidate: EdgeProjectionCandidate
    ) -> [RoutedSegment]? {
        var distances: [RouterNode: Double] = [.start: 0]
        var previous: [RouterNode: (node: RouterNode, neighbor: RouteNeighbor)] = [:]
        var unvisited = Set(nodes.map(RouterNode.graph))
        unvisited.insert(.start)
        unvisited.insert(.end)

        while !unvisited.isEmpty {
            guard let current = unvisited.min(by: {
                (distances[$0] ?? .infinity) < (distances[$1] ?? .infinity)
            }) else {
                break
            }

            let currentDistance = distances[current] ?? .infinity
            if currentDistance == .infinity {
                break
            }

            if current == .end {
                break
            }

            unvisited.remove(current)

            for neighbor in neighbors(of: current, startCandidate: startCandidate, endCandidate: endCandidate)
            where unvisited.contains(neighbor.node) {
                let candidateDistance = currentDistance + neighbor.weightedDistanceFeet
                if candidateDistance < (distances[neighbor.node] ?? .infinity) {
                    distances[neighbor.node] = candidateDistance
                    previous[neighbor.node] = (current, neighbor)
                }
            }
        }

        guard let endDistance = distances[.end], endDistance < .infinity else {
            return nil
        }

        var reversedSegments: [RoutedSegment] = []
        var current: RouterNode = .end

        while current != .start {
            guard let step = previous[current] else {
                return nil
            }
            let neighbor = step.neighbor
            reversedSegments.append(
                RoutedSegment(
                    startCoordinate: neighbor.startCoordinate,
                    endCoordinate: neighbor.endCoordinate,
                    roadName: neighbor.roadName,
                    normalizedRoadName: neighbor.normalizedRoadName,
                    highwayTypes: neighbor.highwayTypes,
                    displayName: neighbor.displayName,
                    roadFamily: GraphEdge.roadFamily(
                        for: neighbor.normalizedRoadName,
                        highwayTypes: neighbor.highwayTypes
                    ),
                    isGeometrySegment: neighbor.normalizedRoadName == "unnamed" &&
                        (neighbor.highwayTypes.contains("service") || neighbor.highwayTypes.contains("pedestrian")),
                    distanceFeet: neighbor.rawDistanceFeet,
                    weightedDistanceFeet: neighbor.weightedDistanceFeet,
                    bearingDegrees: Self.bearingDegrees(
                        from: neighbor.startCoordinate,
                        to: neighbor.endCoordinate
                    )
                )
            )
            current = step.node
        }

        return reversedSegments.reversed()
    }

    private func neighbors(
        of node: RouterNode,
        startCandidate: EdgeProjectionCandidate,
        endCandidate: EdgeProjectionCandidate
    ) -> [RouteNeighbor] {
        switch node {
        case .start:
            return syntheticNeighbors(from: startCandidate, includeDirectEnd: true, endCandidate: endCandidate)

        case .end:
            return []

        case .graph(let graphNode):
            var neighbors = (adjacency[graphNode] ?? []).map { edge in
                let destination = edge.otherNode(from: graphNode)
                return RouteNeighbor(
                    node: .graph(destination),
                    rawDistanceFeet: edge.distanceFeet,
                    weightedDistanceFeet: edge.weightedDistanceFeet,
                    roadName: edge.roadName,
                    normalizedRoadName: edge.normalizedRoadName,
                    highwayTypes: edge.highwayTypes,
                    displayName: edge.displayName,
                    startCoordinate: graphNode.coordinate,
                    endCoordinate: destination.coordinate
                )
            }

            if graphNode == endCandidate.edge.nodeA {
                neighbors.append(syntheticToEndpointNeighbor(from: graphNode, candidate: endCandidate, toward: .nodeA))
            }
            if graphNode == endCandidate.edge.nodeB {
                neighbors.append(syntheticToEndpointNeighbor(from: graphNode, candidate: endCandidate, toward: .nodeB))
            }

            return neighbors
        }
    }

    private func syntheticNeighbors(
        from candidate: EdgeProjectionCandidate,
        includeDirectEnd: Bool,
        endCandidate: EdgeProjectionCandidate
    ) -> [RouteNeighbor] {
        let edge = candidate.edge
        let toNodeADistanceFeet = edge.distanceFeet * candidate.fractionAlongEdge
        let toNodeBDistanceFeet = edge.distanceFeet - toNodeADistanceFeet
        let toNodeAWeightedFeet = edge.weightedDistanceFeet * candidate.fractionAlongEdge
        let toNodeBWeightedFeet = edge.weightedDistanceFeet - toNodeAWeightedFeet

        var neighbors = [
            RouteNeighbor(
                node: .graph(edge.nodeA),
                rawDistanceFeet: toNodeADistanceFeet,
                weightedDistanceFeet: toNodeAWeightedFeet,
                roadName: edge.roadName,
                normalizedRoadName: edge.normalizedRoadName,
                highwayTypes: edge.highwayTypes,
                displayName: edge.displayName,
                startCoordinate: candidate.projectedCoordinate,
                endCoordinate: edge.nodeA.coordinate
            ),
            RouteNeighbor(
                node: .graph(edge.nodeB),
                rawDistanceFeet: toNodeBDistanceFeet,
                weightedDistanceFeet: toNodeBWeightedFeet,
                roadName: edge.roadName,
                normalizedRoadName: edge.normalizedRoadName,
                highwayTypes: edge.highwayTypes,
                displayName: edge.displayName,
                startCoordinate: candidate.projectedCoordinate,
                endCoordinate: edge.nodeB.coordinate
            )
        ]

        if includeDirectEnd && candidate.edge.key == endCandidate.edge.key {
            let sharedFraction = abs(candidate.fractionAlongEdge - endCandidate.fractionAlongEdge)
            let rawDistanceFeet = edge.distanceFeet * sharedFraction
            let weightedDistanceFeet = edge.weightedDistanceFeet * sharedFraction

            neighbors.append(
                RouteNeighbor(
                    node: .end,
                    rawDistanceFeet: rawDistanceFeet,
                    weightedDistanceFeet: weightedDistanceFeet,
                    roadName: edge.roadName,
                    normalizedRoadName: edge.normalizedRoadName,
                    highwayTypes: edge.highwayTypes,
                    displayName: edge.displayName,
                    startCoordinate: candidate.projectedCoordinate,
                    endCoordinate: endCandidate.projectedCoordinate
                )
            )
        }

        return neighbors
    }

    private enum SyntheticEndpoint {
        case nodeA
        case nodeB
    }

    private func syntheticToEndpointNeighbor(
        from graphNode: GraphNode,
        candidate: EdgeProjectionCandidate,
        toward endpoint: SyntheticEndpoint
    ) -> RouteNeighbor {
        let edge = candidate.edge
        let towardNodeA = endpoint == .nodeA
        let rawDistanceFeet = towardNodeA
            ? edge.distanceFeet * candidate.fractionAlongEdge
            : edge.distanceFeet * (1.0 - candidate.fractionAlongEdge)
        let weightedDistanceFeet = towardNodeA
            ? edge.weightedDistanceFeet * candidate.fractionAlongEdge
            : edge.weightedDistanceFeet * (1.0 - candidate.fractionAlongEdge)

        return RouteNeighbor(
            node: .end,
            rawDistanceFeet: rawDistanceFeet,
            weightedDistanceFeet: weightedDistanceFeet,
            roadName: edge.roadName,
            normalizedRoadName: edge.normalizedRoadName,
            highwayTypes: edge.highwayTypes,
            displayName: edge.displayName,
            startCoordinate: graphNode.coordinate,
            endCoordinate: candidate.projectedCoordinate
        )
    }

    private func edgeCandidates(
        near coordinate: CLLocationCoordinate2D,
        limit: Int
    ) -> [EdgeProjectionCandidate] {
        let candidates = edges
            .map { candidate(for: coordinate, on: $0) }
            .filter { $0.distanceMeters <= candidateSnapThresholdMeters }
            .sorted { lhs, rhs in
                if lhs.distanceMeters == rhs.distanceMeters {
                    return lhs.edge.weightedDistanceFeet < rhs.edge.weightedDistanceFeet
                }
                return lhs.distanceMeters < rhs.distanceMeters
            }

        return Array(candidates.prefix(limit))
    }

    private func nearestEdgeDistance(to coordinate: CLLocationCoordinate2D) -> Double? {
        edges
            .map { candidate(for: coordinate, on: $0).distanceMeters }
            .min()
    }

    private func candidate(
        for coordinate: CLLocationCoordinate2D,
        on edge: GraphEdge
    ) -> EdgeProjectionCandidate {
        let projection = Self.project(coordinate, onto: edge)
        return EdgeProjectionCandidate(
            edge: edge,
            projectedCoordinate: projection.coordinate,
            fractionAlongEdge: projection.fraction,
            distanceMeters: projection.distanceMeters
        )
    }

    private func buildNavigationWaypoints(
        from segments: [RoutedSegment],
        startDisplayName: String,
        destinationDisplayName: String
    ) -> NavigationBuildResult {
        guard let firstSegment = segments.first else {
            return NavigationBuildResult(
                waypoints: [],
                maneuverDescriptions: [],
                firstManeuverIsUTurn: false
            )
        }

        let startCoordinate = firstSegment.startCoordinate
        let destinationCoordinate = segments.last?.endCoordinate ?? startCoordinate
        let totalDistanceFeet = segments.reduce(0.0) { $0 + $1.distanceFeet }

        if totalDistanceFeet < 1.0 {
            return NavigationBuildResult(
                waypoints: [
                    Waypoint(
                        name: destinationDisplayName,
                        coordinate: destinationCoordinate,
                        action: .destination
                    )
                ],
                maneuverDescriptions: [
                    "DESTINATION after 0ft via \(destinationDisplayName)"
                ],
                firstManeuverIsUTurn: false
            )
        }

        var waypoints: [Waypoint] = [
            Waypoint(name: startDisplayName, coordinate: startCoordinate, action: .start)
        ]
        var maneuverDescriptions: [String] = []
        var distanceSinceLastWaypoint = 0.0
        var distanceFromStart = 0.0
        var maneuverNumber = 0
        let startingRoadFamily = firstSegment.roadFamily

        for index in 1..<segments.count {
            let previous = segments[index - 1]
            let current = segments[index]
            distanceFromStart += previous.distanceFeet
            distanceSinceLastWaypoint += previous.distanceFeet

            let angleDifference = Self.normalizedAngleDifference(
                current.bearingDegrees - previous.bearingDegrees
            )
            let absoluteAngle = abs(angleDifference)
            let sameNamedRoad = previous.normalizedRoadName != "unnamed" &&
                previous.normalizedRoadName == current.normalizedRoadName
            let sameRoadContinuation = sameNamedRoad && absoluteAngle < 60.0
            let geometryContinuation = previous.isGeometrySegment &&
                current.isGeometrySegment &&
                absoluteAngle < 60.0

            if sameRoadContinuation || geometryContinuation {
                continue
            }

            let roadFamilyChanged = previous.roadFamily != current.roadFamily
            let shouldEmit = (roadFamilyChanged && absoluteAngle >= 25.0) ||
                (!roadFamilyChanged && absoluteAngle >= 60.0 &&
                    distanceSinceLastWaypoint >= minimumDistanceBetweenInstructionsFeet)

            if !shouldEmit {
                continue
            }

            if distanceFromStart <= shortInitialTurnSuppressionFeet &&
                previous.roadFamily == startingRoadFamily &&
                current.roadFamily == startingRoadFamily {
                continue
            }

            let classification = Self.classifyTurn(angleDifference)
            if waypoints.count == 1 && classification.isUTurn {
                return NavigationBuildResult(
                    waypoints: [],
                    maneuverDescriptions: [],
                    firstManeuverIsUTurn: true
                )
            }

            let action = classification.navigationAction
            let locationName = current.displayName
            maneuverNumber += 1
            waypoints.append(
                Waypoint(
                    name: locationName,
                    coordinate: current.startCoordinate,
                    action: action,
                    maneuverNumber: maneuverNumber
                )
            )
            let debugLabel = Self.maneuverDebugLabel(for: action, number: maneuverNumber)
            maneuverDescriptions.append(
                String(
                    format: "%@ after %.0fft via %@",
                    debugLabel,
                    distanceSinceLastWaypoint,
                    locationName
                )
            )
            distanceSinceLastWaypoint = 0.0
        }

        let remainingDistance = distanceSinceLastWaypoint + (segments.last?.distanceFeet ?? 0.0)
        waypoints.append(
            Waypoint(
                name: destinationDisplayName,
                coordinate: destinationCoordinate,
                action: .destination
            )
        )
        maneuverDescriptions.append(
            String(
                format: "DESTINATION after %.0fft via %@",
                remainingDistance,
                destinationDisplayName
            )
        )

        return NavigationBuildResult(
            waypoints: waypoints,
            maneuverDescriptions: maneuverDescriptions,
            firstManeuverIsUTurn: false
        )
    }

    private func headingPenalty(
        firstSegmentBearingDegrees: Double?,
        travelHeadingDegrees: Double?
    ) -> Double {
        guard let firstSegmentBearingDegrees,
              let travelHeadingDegrees else {
            return 0
        }

        let mismatch = abs(Self.normalizedAngleDifference(firstSegmentBearingDegrees - travelHeadingDegrees))

        switch mismatch {
        case ...45:
            return 0
        case ...90:
            return 50
        default:
            return 200
        }
    }

    private static func maneuverDebugLabel(for action: NavigationAction, number: Int) -> String {
        switch action {
        case .left, .right:
            return "TURN \(number) \(action.instructionText.uppercased())"
        case .straight:
            return "STEP \(number) \(action.instructionText.uppercased())"
        case .start:
            return "START"
        case .destination:
            return "DESTINATION"
        }
    }

    private static func classifyTurn(_ angleDifference: Double) -> TurnClassification {
        let absoluteAngle = abs(angleDifference)

        if absoluteAngle < 45 {
            return .straight
        }
        if absoluteAngle > 135 {
            return angleDifference >= 0 ? .uTurnRight : .uTurnLeft
        }
        return angleDifference >= 0 ? .right : .left
    }

    private static func routeCoordinates(from segments: [RoutedSegment]) -> [CLLocationCoordinate2D] {
        guard let firstSegment = segments.first else { return [] }

        var coordinates: [CLLocationCoordinate2D] = [firstSegment.startCoordinate]

        for segment in segments {
            if !approximatelyEqual(coordinates.last, segment.startCoordinate) {
                coordinates.append(segment.startCoordinate)
            }
            if !approximatelyEqual(coordinates.last, segment.endCoordinate) {
                coordinates.append(segment.endCoordinate)
            }
        }

        return coordinates
    }

    private static func makeEdge(
        nodeA: GraphNode,
        nodeB: GraphNode,
        roadName: String,
        highwayTypes: [String],
        distanceFeet: Double
    ) -> GraphEdge {
        let normalizedRoadName = normalizedRoadName(for: roadName)
        let cleanedDistanceFeet = max(distanceFeet, 1.0)
        let weightedDistanceFeet = cleanedDistanceFeet * roadMultiplier(
            normalizedRoadName: normalizedRoadName,
            highwayTypes: highwayTypes
        )

        return GraphEdge(
            key: GraphEdgeKey(nodeA, nodeB),
            nodeA: nodeA,
            nodeB: nodeB,
            roadName: roadName,
            normalizedRoadName: normalizedRoadName,
            highwayTypes: highwayTypes,
            displayName: displayName(for: roadName, highwayTypes: highwayTypes),
            distanceFeet: cleanedDistanceFeet,
            weightedDistanceFeet: weightedDistanceFeet
        )
    }

    private static func merge(_ lhs: GraphEdge, with rhs: GraphEdge) -> GraphEdge {
        let roadName: String
        if lhs.roadName == "Unnamed" && rhs.roadName != "Unnamed" {
            roadName = rhs.roadName
        } else {
            roadName = lhs.roadName
        }

        let highwayTypes = Array(Set(lhs.highwayTypes + rhs.highwayTypes)).sorted()
        let minimumDistanceFeet = min(lhs.distanceFeet, rhs.distanceFeet)

        return makeEdge(
            nodeA: lhs.nodeA,
            nodeB: lhs.nodeB,
            roadName: roadName,
            highwayTypes: highwayTypes,
            distanceFeet: minimumDistanceFeet
        )
    }

    private static func cleanedRoadName(_ roadName: String) -> String {
        let trimmed = roadName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        return trimmed.isEmpty ? "Unnamed" : trimmed
    }

    private static func displayName(for roadName: String, highwayTypes: [String]) -> String {
        if roadName != "Unnamed" {
            return roadName
        }

        let friendlyTypes = highwayTypes.map { type in
            type
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }

        return friendlyTypes.isEmpty ? "Unnamed Path" : friendlyTypes.joined(separator: " / ")
    }

    private static func normalizedRoadName(for roadName: String) -> String {
        let lowered = roadName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        return lowered.isEmpty ? "unnamed" : lowered
    }

    private static func normalizedHighwayTypes(_ highwayTypes: String) -> [String] {
        let splitValues = highwayTypes
            .split(separator: ",")
            .map { component in
                component
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .filter { !$0.isEmpty }

        return splitValues.isEmpty ? ["unknown"] : splitValues
    }

    private static func roadMultiplier(
        normalizedRoadName: String,
        highwayTypes: [String]
    ) -> Double {
        if highwayTypes.contains("service") {
            return 1.0
        }
        if highwayTypes.contains("pedestrian") {
            return 1.05
        }
        if highwayTypes.contains("footway") {
            return normalizedRoadName == "unnamed" ? 2.5 : 1.25
        }
        return 1.6
    }

    private static func parseRow(
        _ row: [String],
        mapping: CSVHeaderMapping
    ) -> (lat1: Double, lon1: Double, lat2: Double, lon2: Double, roadName: String, highwayTypes: String, distanceFeet: Double)? {
        let requiredIndices = [
            mapping.lat1,
            mapping.lon1,
            mapping.lat2,
            mapping.lon2,
            mapping.roadName,
            mapping.highwayTypes,
            mapping.distanceFeet
        ]

        guard row.count > (requiredIndices.max() ?? 0),
              let lat1 = Double(row[mapping.lat1]),
              let lon1 = Double(row[mapping.lon1]),
              let lat2 = Double(row[mapping.lat2]),
              let lon2 = Double(row[mapping.lon2]),
              let distanceFeet = Double(row[mapping.distanceFeet]) else {
            return nil
        }

        return (
            lat1: lat1,
            lon1: lon1,
            lat2: lat2,
            lon2: lon2,
            roadName: row[mapping.roadName],
            highwayTypes: row[mapping.highwayTypes],
            distanceFeet: distanceFeet
        )
    }

    private static func headerMapping(for headerRow: [String]) -> CSVHeaderMapping? {
        func index(for aliases: [String]) -> Int? {
            let normalizedHeaders = headerRow.map(normalizedHeader)
            return normalizedHeaders.firstIndex { aliases.contains($0) }
        }

        guard let lat1 = index(for: ["intersection1lat", "startlat"]),
              let lon1 = index(for: ["intersection1lon", "startlon"]),
              let lat2 = index(for: ["intersection2lat", "endlat"]),
              let lon2 = index(for: ["intersection2lon", "endlon"]),
              let roadName = index(for: ["roadname"]),
              let highwayTypes = index(for: ["highwaytypes", "roadtype"]),
              let distanceFeet = index(for: ["distanceft", "distancefts"]) else {
            return nil
        }

        return CSVHeaderMapping(
            lat1: lat1,
            lon1: lon1,
            lat2: lat2,
            lon2: lon2,
            roadName: roadName,
            highwayTypes: highwayTypes,
            distanceFeet: distanceFeet
        )
    }

    private static func normalizedHeader(_ value: String) -> String {
        let lowered = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        return String(
            lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        )
    }

    private static func parseCSV(_ contents: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(contents)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if inQuotes && index + 1 < characters.count && characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if character == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r") && !inQuotes {
                row.append(field)
                if !(row.count == 1 && row[0].isEmpty) {
                    rows.append(row)
                }
                row = []
                field = ""

                if character == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" {
                    index += 1
                }
            } else {
                field.append(character)
            }

            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    private static func project(
        _ coordinate: CLLocationCoordinate2D,
        onto edge: GraphEdge
    ) -> (coordinate: CLLocationCoordinate2D, fraction: Double, distanceMeters: Double) {
        let averageLatitude = (edge.nodeA.latitude + edge.nodeB.latitude + coordinate.latitude) / 3.0
        let latitudeScale = 111_132.92
        let longitudeScale = 111_412.84 * cos(averageLatitude * .pi / 180.0)

        let ax = 0.0
        let ay = 0.0
        let bx = (edge.nodeB.longitude - edge.nodeA.longitude) * longitudeScale
        let by = (edge.nodeB.latitude - edge.nodeA.latitude) * latitudeScale
        let px = (coordinate.longitude - edge.nodeA.longitude) * longitudeScale
        let py = (coordinate.latitude - edge.nodeA.latitude) * latitudeScale

        let dx = bx - ax
        let dy = by - ay
        let denominator = (dx * dx) + (dy * dy)
        let rawFraction = denominator == 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / denominator
        let fraction = max(0, min(1, rawFraction))

        let projectedX = ax + fraction * dx
        let projectedY = ay + fraction * dy
        let distanceMeters = hypot(px - projectedX, py - projectedY)
        let projectedLongitude = edge.nodeA.longitude + (projectedX / longitudeScale)
        let projectedLatitude = edge.nodeA.latitude + (projectedY / latitudeScale)

        return (
            coordinate: CLLocationCoordinate2D(latitude: projectedLatitude, longitude: projectedLongitude),
            fraction: fraction,
            distanceMeters: distanceMeters
        )
    }

    private static func bearingDegrees(
        from start: GraphNode,
        to end: GraphNode
    ) -> Double {
        bearingDegrees(from: start.coordinate, to: end.coordinate)
    }

    private static func bearingDegrees(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        let deltaLongitude = lon2 - lon1
        let x = sin(deltaLongitude) * cos(lat2)
        let y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)

        return atan2(x, y) * 180 / .pi
    }

    private static func normalizedAngleDifference(_ angle: Double) -> Double {
        var normalized = angle
        while normalized > 180 {
            normalized -= 360
        }
        while normalized < -180 {
            normalized += 360
        }
        return normalized
    }

    private static func normalizedHeading(_ heading: Double?) -> Double? {
        guard let heading else { return nil }
        var normalized = heading.truncatingRemainder(dividingBy: 360)
        if normalized < 0 {
            normalized += 360
        }
        return normalized
    }

    private static func haversineDistanceMeters(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        let deltaLat = lat2 - lat1
        let deltaLon = lon2 - lon1

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }

    private static func approximatelyEqual(
        _ lhs: CLLocationCoordinate2D?,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        guard let lhs else { return false }
        return haversineDistanceMeters(from: lhs, to: rhs) < 0.1
    }
}
