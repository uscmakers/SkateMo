import cv2

def main():
    # Try a few indices; use AVFoundation backend on macOS
    for idx in range(5):
        cap = cv2.VideoCapture(idx, cv2.CAP_AVFOUNDATION)
        if cap.isOpened():
            print(f"Trying camera index {idx}")
            ret, frame = cap.read()
            if not ret:
                print("  -> failed to grab frame")
                cap.release()
                continue

            cv2.imshow(f"Camera {idx}", frame)
            print("  -> press q to close this preview")

            while True:
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break

            cap.release()
            cv2.destroyAllWindows()
        else:
            print(f"Camera index {idx} not available")

if __name__ == "__main__":
    main()