import cv2

cap = cv2.VideoCapture(1) # 0 for built in camera, 1 for continuity camera

while True:
    ret, frame = cap.read()
    if not ret:
        break

    cv2.imshow("Webcam", frame)

    if cv2.waitKey(1) == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
