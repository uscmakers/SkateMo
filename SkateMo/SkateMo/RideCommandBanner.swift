//
//  RideCommandBanner.swift
//  SkateMo
//

import SwiftUI

struct RideCommandBanner: View {
    let command: BoardCommand
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(backgroundColor.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var backgroundColor: Color {
        switch command {
        case .idle:
            return .gray
        case .forward:
            return .blue
        case .turnLeft, .turnRight:
            return .orange
        case .stopForObstacle:
            return .red
        case .arrived:
            return .green
        }
    }
}
