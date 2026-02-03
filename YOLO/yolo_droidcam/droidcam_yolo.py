import cv2
from ultralytics import YOLO

# 1. CHANGE THIS: use your phone's IP and port from the DroidCam app
STREAM_URL = "http://10.23.139.109:4747/video"  # example

def main():
    # 2. Load a small YOLO model (pretrained on COCO)
    model = YOLO("yolov8n.pt")  # auto-downloads first time

    # 3. Open the DroidCam stream
    cap = cv2.VideoCapture(STREAM_URL)

    if not cap.isOpened():
        print("Error: Could not open video stream. Check URL / Wi-Fi / DroidCam app.")
        return

    while True:
        ret, frame = cap.read()
        if not ret:
            print("Error: failed to read frame")
            break

        # 4. Run YOLO on the frame
        results = model(frame)[0]  # first (only) result

        # 5. (Optional) here you can do your own post-processing logic
        # e.g., print person detections:
        for box in results.boxes:
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            class_name = results.names[cls_id]

            if class_name == "person" and conf > 0.7:
                print(f"Person {conf:.2f} at {x1,y1,x2,y2}")

        # 6. Draw boxes + labels on the frame for visualization
        annotated = results.plot()

        cv2.imshow("YOLO + iPhone via DroidCam", annotated)

        # Press 'q' to quit
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()