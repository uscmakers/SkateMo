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

enum BoardBLECommand: String, Equatable {
    case forward = "straight"
    case back = "back"
    case turnLeft = "left"
    case turnRight = "right"
    case stop = "stop"

    init(boardCommand: BoardCommand) {
        switch boardCommand {
        case .forward:
            self = .forward
        case .turnLeft:
            self = .turnLeft
        case .turnRight:
            self = .turnRight
        case .idle, .stopForObstacle, .arrived:
            self = .stop
        }
    }

    init?(notificationString: String) {
        let normalized = notificationString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "straight", "forward", "ack:straight", "ack:forward":
            self = .forward
        case "back", "ack:back":
            self = .back
        case "left", "ack:left":
            self = .turnLeft
        case "right", "ack:right":
            self = .turnRight
        case "stop", "ack:stop":
            self = .stop
        default:
            return nil
        }
    }

    var displayText: String {
        switch self {
        case .forward:
            return "FORWARD"
        case .back:
            return "BACK"
        case .turnLeft:
            return "TURN LEFT"
        case .turnRight:
            return "TURN RIGHT"
        case .stop:
            return "STOP"
        }
    }
    var transportString: String {
        rawValue
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
