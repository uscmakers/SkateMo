//
//  CameraView.swift
//  SkateMo
//
import SwiftUI

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var objectDetector = ObjectDetector()
    @StateObject private var obstacleEvaluator = ObstacleEvaluator()

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
                    Text("Starting camera...")
                        .foregroundColor(.white)
                }

                ForwardCorridorOverlay(viewSize: geometry.size, state: obstacleEvaluator.state)

                // Bounding boxes overlay
                ForEach(obstacleEvaluator.evaluatedObstacles) { obstacle in
                    BoundingBoxView(
                        obstacle: obstacle,
                        viewSize: geometry.size
                    )
                }

                // Status + detection overlay
                VStack {
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
                    .padding(.top, 50)
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
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onReceive(objectDetector.$detections) { detections in
            obstacleEvaluator.update(with: detections)
        }
        .onAppear {
            cameraManager.onFrameCaptured = { pixelBuffer in
                objectDetector.detect(pixelBuffer: pixelBuffer)
            }
            cameraManager.start()
        }
        .onDisappear {
            cameraManager.stop()
        }
    }
}

struct BoundingBoxView: View {
    let obstacle: EvaluatedObstacle
    let viewSize: CGSize

    var body: some View {
        let rect = convertBoundingBox(obstacle.detection.boundingBox, to: viewSize)

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
    private func convertBoundingBox(_ boundingBox: CGRect, to viewSize: CGSize) -> CGRect {
        let x = boundingBox.minX * viewSize.width
        let y = (1 - boundingBox.maxY) * viewSize.height  // Flip Y axis
        let width = boundingBox.width * viewSize.width
        let height = boundingBox.height * viewSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct ForwardCorridorOverlay: View {
    let viewSize: CGSize
    let state: ObstacleState

    var body: some View {
        let rect = convertBoundingBox(ObstacleEvaluator.corridorRect, to: viewSize)

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

    private func convertBoundingBox(_ boundingBox: CGRect, to viewSize: CGSize) -> CGRect {
        let x = boundingBox.minX * viewSize.width
        let y = (1 - boundingBox.maxY) * viewSize.height
        let width = boundingBox.width * viewSize.width
        let height = boundingBox.height * viewSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

#Preview {
    CameraView()
}
