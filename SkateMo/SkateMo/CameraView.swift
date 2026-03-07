//
//  CameraView.swift
//  SkateMo
//
import SwiftUI

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var objectDetector = ObjectDetector()

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

                // Bounding boxes overlay
                ForEach(objectDetector.detections) { detection in
                    BoundingBoxView(
                        detection: detection,
                        viewSize: geometry.size
                    )
                }

                // Detection count overlay
                VStack {
                    HStack {
                        Text("\(objectDetector.detections.count) objects")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    .padding(.top, 50)
                    .padding(.horizontal)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
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
    let detection: Detection
    let viewSize: CGSize

    var body: some View {
        let rect = convertBoundingBox(detection.boundingBox, to: viewSize)

        ZStack(alignment: .topLeading) {
            // Bounding box rectangle
            Rectangle()
                .stroke(Color.green, lineWidth: 3)
                .frame(width: rect.width, height: rect.height)

            // Label background
            Text("\(detection.label) \(Int(detection.confidence * 100))%")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green)
                .offset(y: -20)
        }
        .position(x: rect.midX, y: rect.midY)
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

#Preview {
    CameraView()
}
