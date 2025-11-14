String command = "";

// Motor direction pins
const int IN1 = 9;     
const int IN2 = 10;

void setup() {
  Serial.begin(9600);

  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);

  // Start stopped
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
}

void loop() {

  if (Serial.available()) {
    command = Serial.readStringUntil('\n');
    command.trim();

    if (command == "up") {
      moveForward();
    }

    if (command == "down") {
      moveBackward();
    }
  }
}

void moveForward() {
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  delay(1000);
  stopMotor();
}

void moveBackward() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  delay(1000);
  stopMotor();
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
}
