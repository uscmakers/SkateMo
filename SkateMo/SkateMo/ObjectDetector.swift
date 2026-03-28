//
//  ObjectDetector.swift
//  SkateMo
//
import Vision
import CoreML
import CoreGraphics

struct Detection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect  // Normalized coordinates (0-1)
}

class ObjectDetector: ObservableObject {
    @Published var detections: [Detection] = []

    private var request: VNCoreMLRequest?
    private let detectionQueue = DispatchQueue(label: "detectionQueue", qos: .userInitiated)
    private let confidenceThreshold: Float = 0.5

    // Classes relevant to obstacle detection for sidewalk/campus riding.
    private let allowedClasses: Set<String> = [
        "person",
        "car",
        "bicycle",
        "motorcycle",
        "bus",
        "truck",
        "dog",
        "skateboard"
    ]

    // COCO class labels (80 classes)
    private let cocoLabels = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake",
        "chair", "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop",
        "mouse", "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    ]

    init() {
        setupModel()
    }

    private func setupModel() {
        // Try to load YOLOv8 model - check for mlpackage first, then mlmodelc
        if let modelURL = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc") ??
                          Bundle.main.url(forResource: "yolov8n", withExtension: "mlpackage") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all  // Use Neural Engine + GPU + CPU
                let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
                let vnModel = try VNCoreMLModel(for: mlModel)
                request = VNCoreMLRequest(model: vnModel, completionHandler: handleDetection)
                request?.imageCropAndScaleOption = .scaleFill
                print("Loaded YOLOv8 model successfully")
            } catch {
                print("Failed to load YOLOv8 model: \(error)")
            }
        } else {
            print("YOLOv8 model not found in bundle - using fallback detection")
        }
    }

    func detect(pixelBuffer: CVPixelBuffer) {
        detectionQueue.async { [weak self] in
            guard let self = self else { return }

            if let request = self.request {
                // Use YOLO model
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                try? handler.perform([request])
            } else {
                // Fallback: detect humans for prototyping
                self.detectWithBuiltIn(pixelBuffer: pixelBuffer)
            }
        }
    }

    private func detectWithBuiltIn(pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        let humanRequest = VNDetectHumanRectanglesRequest { [weak self] request, error in
            guard let results = request.results as? [VNHumanObservation] else { return }

            let humanDetections = results.compactMap { observation -> Detection? in
                guard self?.allowedClasses.contains("person") == true else { return nil }
                return Detection(
                    label: "person",
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox
                )
            }

            DispatchQueue.main.async {
                self?.detections = humanDetections
            }
        }
        humanRequest.upperBodyOnly = false

        try? handler.perform([humanRequest])
    }

    private func handleDetection(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            // If no recognized objects, try to parse as core ML output
            return
        }

        let newDetections = results.compactMap { observation -> Detection? in
            guard let topLabel = observation.labels.first,
                  topLabel.confidence >= confidenceThreshold else { return nil }

            // Map the label identifier to COCO class name if it's an index
            let labelName: String
            if let index = Int(topLabel.identifier), index < cocoLabels.count {
                labelName = cocoLabels[index]
            } else {
                labelName = topLabel.identifier
            }

            // Filter to only allowed classes
            guard allowedClasses.contains(labelName) else { return nil }

            return Detection(
                label: labelName,
                confidence: topLabel.confidence,
                boundingBox: observation.boundingBox
            )
        }

        DispatchQueue.main.async { [weak self] in
            self?.detections = newDetections
        }
    }
}
