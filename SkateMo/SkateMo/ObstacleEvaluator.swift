//
//  ObstacleEvaluator.swift
//  SkateMo
//

import Foundation
import SwiftUI

enum ObstacleState: String {
    case go = "GO"
    case caution = "CAUTION"
    case stop = "STOP"

    var color: Color {
        switch self {
        case .go: return .green
        case .caution: return .yellow
        case .stop: return .red
        }
    }
}

enum ObstacleSeverity {
    case low
    case caution
    case high

    var color: Color {
        switch self {
        case .low: return .gray
        case .caution: return .yellow
        case .high: return .red
        }
    }
}

struct EvaluatedObstacle: Identifiable {
    let id = UUID()
    let detection: Detection
    let severity: ObstacleSeverity
    let riskScore: Double
    let estimatedDistanceMeters: Double
    let timeToCollisionSeconds: Double?
}

final class ObstacleEvaluator: ObservableObject {
    // Vision uses a normalized coordinate system with a bottom-left origin.
    static let corridorRect = CGRect(x: 0.22, y: 0.0, width: 0.56, height: 0.85)

    @Published var evaluatedObstacles: [EvaluatedObstacle] = []
    @Published var state: ObstacleState = .go
    @Published var nearestObstacleDistanceMeters: Double?
    @Published var timeToCollisionSeconds: Double?

    private let stopFrameThreshold = 3
    private let cautionFrameThreshold = 2
    private let clearFrameThreshold = 2
    private let assumedSpeedMetersPerSecond = 3.0

    private var highRiskFrames = 0
    private var cautionFrames = 0
    private var clearFrames = 0

    func update(with detections: [Detection]) {
        let evaluated = detections.map(evaluate)
        evaluatedObstacles = evaluated

        let relevant = evaluated.filter { $0.severity != .low }
        nearestObstacleDistanceMeters = relevant.map(\.estimatedDistanceMeters).min()
        if let nearest = nearestObstacleDistanceMeters {
            timeToCollisionSeconds = nearest / assumedSpeedMetersPerSecond
        } else {
            timeToCollisionSeconds = nil
        }

        let hasHighRisk = relevant.contains { $0.severity == .high }
        let hasCautionRisk = hasHighRisk || relevant.contains { $0.severity == .caution }

        if hasHighRisk {
            highRiskFrames += 1
            cautionFrames += 1
            clearFrames = 0
        } else if hasCautionRisk {
            cautionFrames += 1
            highRiskFrames = max(0, highRiskFrames - 1)
            clearFrames = 0
        } else {
            clearFrames += 1
            highRiskFrames = max(0, highRiskFrames - 1)
            cautionFrames = max(0, cautionFrames - 1)
        }

        if highRiskFrames >= stopFrameThreshold {
            state = .stop
            return
        }
        if cautionFrames >= cautionFrameThreshold {
            state = .caution
            return
        }
        if clearFrames >= clearFrameThreshold {
            state = .go
        }
    }

    private func evaluate(_ detection: Detection) -> EvaluatedObstacle {
        let box = detection.boundingBox
        let overlap = box.intersection(Self.corridorRect)
        let overlapArea = normalizedArea(of: overlap)
        let boxArea = max(normalizedArea(of: box), 0.0001)
        let overlapRatio = overlapArea / boxArea

        let insideCorridor = overlapRatio > 0.25
        let proximityScore = clamp(1.0 - Double(box.midY), min: 0.0, max: 1.0)
        let sizeScore = clamp(Double(boxArea) * 7.0, min: 0.0, max: 1.0)
        let confidenceScore = clamp(Double(detection.confidence), min: 0.0, max: 1.0)
        let corridorWeight = insideCorridor ? clamp(overlapRatio, min: 0.3, max: 1.0) : 0.0

        let riskScore = (0.5 * proximityScore + 0.3 * sizeScore + 0.2 * confidenceScore) * corridorWeight
        let estimatedDistance = estimateDistance(fromNormalizedHeight: Double(box.height))
        let ttc = estimatedDistance / assumedSpeedMetersPerSecond

        let severity: ObstacleSeverity
        if !insideCorridor {
            severity = .low
        } else if riskScore >= 0.60 || estimatedDistance <= 2.5 {
            severity = .high
        } else if riskScore >= 0.35 || estimatedDistance <= 5.0 {
            severity = .caution
        } else {
            severity = .low
        }

        return EvaluatedObstacle(
            detection: detection,
            severity: severity,
            riskScore: riskScore,
            estimatedDistanceMeters: estimatedDistance,
            timeToCollisionSeconds: severity == .low ? nil : ttc
        )
    }

    private func estimateDistance(fromNormalizedHeight height: Double) -> Double {
        let safeHeight = max(height, 0.05)
        return clamp(3.2 / safeHeight, min: 0.8, max: 30.0)
    }

    private func normalizedArea(of rect: CGRect) -> Double {
        let width = max(Double(rect.width), 0)
        let height = max(Double(rect.height), 0)
        return width * height
    }

    private func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.max(lower, Swift.min(upper, value))
    }
}
