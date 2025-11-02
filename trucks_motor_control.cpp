#include <Servo.h>
Servo esc;

const int ESC_PIN = 9;          // PWM pin for ESC signal
const int MIN_US = 1000;        // 0% throttle (stop)
const int MAX_US = 2800;        // 40% throttle cap

void setup() {
  esc.attach(ESC_PIN);
  Serial.begin(9600);
  Serial.println("Arming ESC...");

  esc.writeMicroseconds(MIN_US);
  delay(2000);
  Serial.println("ESC armed. Ready.");
}

void loop() {
  Serial.println("Ramping up...");
  for (int us = MIN_US; us <= MAX_US; us += 5) {
    esc.writeMicroseconds(us);
    delay(10);
  }

  Serial.println("Holding 40% speed...");
  delay(1000);

  Serial.println("Ramping down...");
  for (int us = MAX_US; us >= MIN_US; us -= 5) {
    esc.writeMicroseconds(us);
    delay(10);
  }

  delay(1000);
}