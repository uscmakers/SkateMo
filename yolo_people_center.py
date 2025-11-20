from ultralytics import YOLO
import cv2

model = YOLO("yolov8n.pt")

cap = cv2.VideoCapture(0)

if not cap.isOpened():
    print("Error: Cannot open webcam")
    exit()

while True:
    ret, frame = cap.read()
    if not ret:
        break

    H, W = frame.shape[:2]

    # Middle 25% horizontal zone
    left_boundary = int(W * 0.375)
    right_boundary = int(W * 0.625)

    # Vertical halfway line
    half_height = H // 2

    results = model(frame, verbose=False)

    for r in results:
        for box in r.boxes:
            cls = int(box.cls[0])
            conf = float(box.conf[0])

            if cls == 0 and conf > 0.5:
                x1, y1, x2, y2 = map(int, box.xyxy[0])

                cx = (x1 + x2) // 2
                cy = (y1 + y2) // 2

                width = x2 - x1
                height = y2 - y1

                # STEP 1 — horizontally centered?
                in_middle_zone = left_boundary <= cx <= right_boundary

                # STEP 2 — vertically above half?
                in_upper_half = cy < half_height

                # Color logic
                if in_middle_zone and in_upper_half:
                    color = (0, 0, 255)  # RED
                else:
                    color = (0, 255, 0)  # GREEN

                # Draw box + center point
                cv2.rectangle(frame, (x1, y1), (x2, y2), color, 3)
                cv2.circle(frame, (cx, cy), 5, (255, 255, 255), -1)

                # Labels
                cv2.putText(frame,
                            f"Center: ({cx}, {cy})",
                            (x1, y1 - 10),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)

                cv2.putText(frame,
                            f"Size: w={width} h={height}",
                            (x1, y1 - 35),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)

                print(f"cx={cx}, cy={cy}, centered={in_middle_zone}, upper_half={in_upper_half}")

    # Draw visual guides
    cv2.line(frame, (left_boundary, 0), (left_boundary, H), (255, 255, 0), 2)
    cv2.line(frame, (right_boundary, 0), (right_boundary, H), (255, 255, 0), 2)
    cv2.line(frame, (0, half_height), (W, half_height), (0, 255, 255), 2)

    cv2.imshow("YOLO - Combined Horiz + Vert Detection", frame)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
