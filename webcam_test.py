import cv2

cap = cv2.VideoCapture(0)
ret, frame = cap.read()

if ret:
    print("Webcam OK")
else:
    print("Webcam NOT found")

cap.release()

