#define PIN_SLIDE_POT_A 35
String command = "";

// Motor direction pins
const int IN1 = 25;     
const int IN2 = 26;
const int ENA = 27;

// Variable to track the last time we printed to the Serial monitor
unsigned long lastPrintTime = 0; 

void setup() {
  Serial.begin(115200);

  pinMode(PIN_SLIDE_POT_A, INPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(ENA, OUTPUT);

  // Start stopped
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  analogWrite(ENA, 255);
}

void loop() {
  // 1. Only print the pot value every 500 milliseconds to prevent Serial flooding
  if (millis() - lastPrintTime >= 500) {
    int value_slide_pot_a = analogRead(PIN_SLIDE_POT_A);
    Serial.print("Slide Pot value: ");
    Serial.println(value_slide_pot_a);
    
    // Reset the timer
    lastPrintTime = millis(); 
  }
  
  // 2. Check for commands
  if (Serial.available()) {
    command = Serial.readStringUntil('\n');
    command.trim(); // Removes whitespace and hidden carriage returns

    if (command == "up") {
      moveForward();
    }
    else if (command == "down") {
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