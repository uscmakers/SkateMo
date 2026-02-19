#define PIN_SLIDE_POT_A A0
String command = "";

// Motor direction pins
const int IN1 = 5;     
const int IN2 = 4;
const int ENA = 6;


void setup() {
  Serial.begin(9600);

  pinMode(PIN_SLIDE_POT_A, INPUT );
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(ENA, OUTPUT);

  // Start stopped
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  analogWrite(ENA, 255);
}

void loop() {
  int value_slide_pot_a = analogRead(PIN_SLIDE_POT_A);
  Serial.print("Slide Pot value: ");
  Serial.println(value_slide_pot_a);
  
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
  delay(250);
  stopMotor();
}

void moveBackward() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  delay(250);
  stopMotor();
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
}