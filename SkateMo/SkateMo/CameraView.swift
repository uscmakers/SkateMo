//
//  CameraView.swift
//  SkateMo
//
import SwiftUI

struct CameraView: View {
    @ObservedObject var rideSession: RideSessionManager
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var navigationManager: NavigationManager
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var objectDetector: ObjectDetector
    @ObservedObject var obstacleEvaluator: ObstacleEvaluator

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera feed
                if let frame = cameraManager.frame {
                    Image(decorative: frame, scale: 1.0)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Color.black
                    Text(rideSession.rideActive ? "Starting camera..." : "Start a ride to activate camera safety monitoring.")
                        .foregroundColor(.white)
                }

                ForwardCorridorOverlay(
                    viewSize: geometry.size,
                    imageSize: cameraManager.frameSize,
                    state: obstacleEvaluator.state
                )

                // Bounding boxes overlay
                ForEach(obstacleEvaluator.evaluatedObstacles) { obstacle in
                    BoundingBoxView(
                        obstacle: obstacle,
                        viewSize: geometry.size,
                        imageSize: cameraManager.frameSize
                    )
                }

                // Status + detection overlay
                VStack {
                    RideCommandBanner(
                        command: rideSession.bannerCommand,
                        title: rideSession.bannerTitle,
                        subtitle: rideSession.bannerSubtitle
                    )
                    .padding(.top, 50)
                    .padding(.horizontal)

                    HStack {
                        Text("\(objectDetector.detections.count) objects")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(obstacleEvaluator.state.rawValue)
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(obstacleEvaluator.state.color.opacity(0.85))
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        if cameraManager.isUltraWideAvailable {
                            Button {
                                cameraManager.toggleLensMode()
                            } label: {
                                Text(cameraManager.lensMode.rawValue)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.horizontal)

                    Text(rideSession.effectiveCommandSource.displayText)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)

                    HStack {
                        if let nearest = obstacleEvaluator.nearestObstacleDistanceMeters {
                            Text(String(format: "Nearest: %.1fm", nearest))
                        } else {
                            Text("Nearest: --")
                        }

                        Spacer()

                        if let ttc = obstacleEvaluator.timeToCollisionSeconds {
                            Text(String(format: "TTC: %.1fs", ttc))
                        } else {
                            Text("TTC: --")
                        }
                    }
                    .font(.caption2)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)

                    HStack(spacing: 12) {
                        headingStatusChip(
                            title: "Current heading",
                            value: locationManager.travelHeadingDegrees
                        )

                        headingStatusChip(
                            title: "Target heading",
                            value: navigationManager.activeTurnTargetHeadingDegrees
                        )
                    }
                    .padding(.horizontal)

                    HStack {
                        Spacer()
                        Text("Swipe left for debug")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.28))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
    }

    private func headingStatusChip(title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
            Text(headingText(value))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func headingText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f deg", value)
    }
}

struct BoundingBoxView: View {
    let obstacle: EvaluatedObstacle
    let viewSize: CGSize
    let imageSize: CGSize

    var body: some View {
        let rect = convertBoundingBox(obstacle.detection.boundingBox, to: viewSize, imageSize: imageSize)

        ZStack(alignment: .topLeading) {
            // Bounding box rectangle
            Rectangle()
                .stroke(obstacle.severity.color, lineWidth: obstacle.severity == .high ? 4 : 3)
                .frame(width: rect.width, height: rect.height)

            // Label background
            Text(labelText)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(obstacle.severity.color)
                .offset(y: -20)
        }
        .position(x: rect.midX, y: rect.midY)
    }

    private var labelText: String {
        let base = "\(obstacle.detection.label) \(Int(obstacle.detection.confidence * 100))%"
        switch obstacle.severity {
        case .high:
            return "\(base) STOP"
        case .caution:
            return "\(base) CAUTION"
        case .low:
            return base
        }
    }

    // Convert normalized Vision coordinates to view coordinates
    // Vision uses bottom-left origin, SwiftUI uses top-left
    private func convertBoundingBox(_ boundingBox: CGRect, to viewSize: CGSize, imageSize: CGSize) -> CGRect {
        let normalizedRect = CGRect(
            x: boundingBox.minX,
            y: 1 - boundingBox.maxY,
            width: boundingBox.width,
            height: boundingBox.height
        )
        return aspectFillRect(for: normalizedRect, in: viewSize, imageSize: imageSize)
    }
}

struct ForwardCorridorOverlay: View {
    let viewSize: CGSize
    let imageSize: CGSize
    let state: ObstacleState

    var body: some View {
        let rect = convertBoundingBox(ObstacleEvaluator.corridorRect, to: viewSize, imageSize: imageSize)

        ZStack {
            Rectangle()
                .fill(state.color.opacity(0.08))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundColor(state.color.opacity(0.95))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
    }

    private func convertBoundingBox(_ boundingBox: CGRect, to viewSize: CGSize, imageSize: CGSize) -> CGRect {
        let normalizedRect = CGRect(
            x: boundingBox.minX,
            y: 1 - boundingBox.maxY,
            width: boundingBox.width,
            height: boundingBox.height
        )
        return aspectFillRect(for: normalizedRect, in: viewSize, imageSize: imageSize)
    }
}

private func aspectFillRect(for normalizedRect: CGRect, in viewSize: CGSize, imageSize: CGSize) -> CGRect {
    guard viewSize.width > 0, viewSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
        return CGRect(
            x: normalizedRect.minX * viewSize.width,
            y: normalizedRect.minY * viewSize.height,
            width: normalizedRect.width * viewSize.width,
            height: normalizedRect.height * viewSize.height
        )
    }

    let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    let displayedWidth = imageSize.width * scale
    let displayedHeight = imageSize.height * scale
    let xOffset = (viewSize.width - displayedWidth) / 2
    let yOffset = (viewSize.height - displayedHeight) / 2

    return CGRect(
        x: xOffset + normalizedRect.minX * displayedWidth,
        y: yOffset + normalizedRect.minY * displayedHeight,
        width: normalizedRect.width * displayedWidth,
        height: normalizedRect.height * displayedHeight
    )
}

#Preview {
    ContentView()
}
