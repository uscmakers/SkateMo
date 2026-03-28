//
//  BoardCommand.swift
//  SkateMo
//

import Foundation

enum BoardCommand: String, Equatable {
    case idle
    case forward
    case turnLeft
    case turnRight
    case stopForObstacle
    case arrived

    var displayText: String {
        switch self {
        case .idle:
            return "IDLE"
        case .forward:
            return "FORWARD"
        case .turnLeft:
            return "TURN LEFT"
        case .turnRight:
            return "TURN RIGHT"
        case .stopForObstacle:
            return "STOP - OBSTACLE"
        case .arrived:
            return "ARRIVED"
        }
    }

    var isNavigationMovementCommand: Bool {
        switch self {
        case .forward, .turnLeft, .turnRight:
            return true
        case .idle, .stopForObstacle, .arrived:
            return false
        }
    }
}

enum BoardCommandSource: String, Equatable {
    case navigation
    case vision
    case system

    var displayText: String {
        switch self {
        case .navigation:
            return "Navigation"
        case .vision:
            return "Vision Safety Override"
        case .system:
            return "System"
        }
    }
}

enum NavigationAction: String, Equatable {
    case start
    case straight
    case left
    case right
    case destination

    var instructionText: String {
        switch self {
        case .start:
            return "Start"
        case .straight:
            return "Straight"
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .destination:
            return "Destination"
        }
    }

    var boardCommand: BoardCommand {
        switch self {
        case .start, .straight:
            return .forward
        case .left:
            return .turnLeft
        case .right:
            return .turnRight
        case .destination:
            return .arrived
        }
    }
}
