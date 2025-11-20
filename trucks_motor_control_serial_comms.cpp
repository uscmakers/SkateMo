#include <Servo.h>
Servo esc;

const int ESC_PIN = 9;          // PWM pin for ESC signal
const int MIN_US = 1000;        // stop
const int MAX_US = 2800;        // 40% throttle cap

void setup() {
  esc.attach(ESC_PIN);
  Serial.begin(9600);
  Serial.println("Arming ESC...");

  // Arm ESC at MIN_US
  esc.writeMicroseconds(MIN_US);
  delay(2000);
  Serial.println("ESC armed. Ready.");
}

void loop() {
  if (Serial.available() > 0) {
    String command = Serial.readStringUntil('\n');

    if (command == "STOP") {
      esc.writeMicroseconds(MIN_US);
      Serial.println("Motor STOP");
    } 
    else if (command == "MOVE") {
      esc.writeMicroseconds(MAX_US);
      Serial.println("Motor MOVE");
    }
  }
}
