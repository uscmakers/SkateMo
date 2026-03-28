//
//  CameraManager.swift
//  SkateMo
//
import AVFoundation
import CoreImage
import UIKit

enum CameraLensMode: String {
    case standard = "1x"
    case ultraWide = "0.5x"
}

class CameraManager: NSObject, ObservableObject {
    @Published var frame: CGImage?
    @Published private(set) var frameSize: CGSize = .zero
    @Published private(set) var lensMode: CameraLensMode = .standard
    @Published private(set) var isUltraWideAvailable = false

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "cameraSessionQueue")
    private var videoInput: AVCaptureDeviceInput?
    private var deviceOrientationObserver: NSObjectProtocol?

    var onFrameCaptured: ((CVPixelBuffer) -> Void)?

    override init() {
        super.init()
        isUltraWideAvailable = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        deviceOrientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateVideoOrientation()
        }
        setupCamera()
    }

    deinit {
        if let observer = deviceOrientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func setupCamera() {
        sessionQueue.async { [weak self] in
            self?.configureSession(for: .standard, includeOutputSetup: true)
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            self?.updateVideoOrientation()
            self?.captureSession.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    func toggleLensMode() {
        guard isUltraWideAvailable else { return }
        let nextMode: CameraLensMode = lensMode == .standard ? .ultraWide : .standard
        setLensMode(nextMode)
    }

    func setLensMode(_ mode: CameraLensMode) {
        sessionQueue.async { [weak self] in
            self?.configureSession(for: mode, includeOutputSetup: false)
        }
    }

    private func configureSession(for mode: CameraLensMode, includeOutputSetup: Bool) {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        if includeOutputSetup {
            captureSession.sessionPreset = .hd1280x720
        }

        if let existingInput = videoInput {
            captureSession.removeInput(existingInput)
            videoInput = nil
        }

        guard let camera = cameraDevice(for: mode),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("Failed to access \(mode.rawValue) camera")
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            videoInput = input
            DispatchQueue.main.async { [weak self] in
                self?.lensMode = camera.deviceType == .builtInUltraWideCamera ? .ultraWide : .standard
            }
        }

        if includeOutputSetup {
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            if captureSession.outputs.isEmpty, captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
        }

        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(rotationAngle(for: UIDevice.current.orientation)) {
            connection.videoRotationAngle = rotationAngle(for: UIDevice.current.orientation)
        }
    }

    private func cameraDevice(for mode: CameraLensMode) -> AVCaptureDevice? {
        switch mode {
        case .ultraWide:
            if let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
                return ultraWide
            }
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .standard:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
    }

    private func updateVideoOrientation() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let connection = self.videoOutput.connection(with: .video) else { return }

            let angle = self.rotationAngle(for: UIDevice.current.orientation)
            guard connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }

    private func rotationAngle(for orientation: UIDeviceOrientation) -> CGFloat {
        switch orientation {
        case .portrait:
            return 90
        case .landscapeLeft:
            return 0
        case .landscapeRight:
            return 180
        case .portraitUpsideDown:
            return 270
        default:
            return 90
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Send frame for ML processing
        onFrameCaptured?(pixelBuffer)

        // Convert to CGImage for display
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.frame = cgImage
            self?.frameSize = CGSize(width: cgImage.width, height: cgImage.height)
        }
    }
}
