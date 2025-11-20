import cv2
import numpy as np

# Open the default webcam (0)
cap = cv2.VideoCapture(0)

# ---- COLOR RANGE (HSV) ----
# These ranges detect RED. We can change to any color later.
lower_red_1 = np.array([0, 120, 70])
upper_red_1 = np.array([10, 255, 255])

lower_red_2 = np.array([170, 120, 70])
upper_red_2 = np.array([180, 255, 255])

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # Convert BGR → HSV (best for color detection)
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)

    # Build two masks for red (because red wraps around HSV hue)
    mask1 = cv2.inRange(hsv, lower_red_1, upper_red_1)
    mask2 = cv2.inRange(hsv, lower_red_2, upper_red_2)
    mask = mask1 + mask2

    # Remove noise
    kernel = np.ones((5, 5), np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_DILATE, kernel)

    # Find contours (connected areas of color)
    contours, _ = cv2.findContours(mask, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)

    if contours:
        # Pick the largest red blob
        largest = max(contours, key=cv2.contourArea)
        area = cv2.contourArea(largest)

        if area > 500:  # ignore tiny noise
            x, y, w, h = cv2.boundingRect(largest)
            cx = x + w // 2
            cy = y + h // 2

            # Draw detection box + center dot
            cv2.rectangle(frame, (x, y), (x+w, y+h), (0, 0, 255), 2)
            cv2.circle(frame, (cx, cy), 5, (0, 255, 0), -1)

            print(f"Detected object center: ({cx}, {cy}), Area: {area}")

    # Show the camera frame
    cv2.imshow("Camera", frame)

    # Show the color mask (white = detected color)
    cv2.imshow("Mask", mask)

    # Press Q to quit
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
