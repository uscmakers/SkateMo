from ultralytics import YOLO
import cv2

# Load YOLOv8 model (nano is fastest for live webcam)
model = YOLO("yolov8n.pt")

cap = cv2.VideoCapture(0)

if not cap.isOpened():
    print("Error: Cannot open webcam")
    exit()

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # Run YOLO inference
    results = model(frame, verbose=False)

    for r in results:
        for box in r.boxes:
            cls = int(box.cls[0])
            conf = float(box.conf[0])

            # Only detect people (COCO class 0 = person)
            if cls == 0 and conf > 0.5:
                x1, y1, x2, y2 = box.xyxy[0]

                x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)

                # Compute center point
                cx = (x1 + x2) // 2
                cy = (y1 + y2) // 2

                # Draw bounding box
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)

                # Draw center point
                cv2.circle(frame, (cx, cy), 5, (0, 0, 255), -1)

                # Display label
                label = f"Person {conf:.2f}"
                cv2.putText(frame, label, (x1, y1 - 10),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)

                # Optional: print to console
                print(f"Person detected at center: ({cx}, {cy})")

    cv2.imshow("YOLOv8 People Detection", frame)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
