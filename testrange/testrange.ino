// =============================
// Pin Definitions
// =============================
#define PIN_SLIDE_POT_A 35

// Motor direction pins
const int IN1 = 25;
const int IN2 = 26;
const int ENA = 27;

// PWM Settings (Using your working ESP32 API)
const int pwmFreq = 5000;
const int pwmResolution = 8;
const int motorSpeed = 255; 

String command = "";

void setup() {
  // Set Serial Monitor to 115200 baud!
  Serial.begin(115200); 

  pinMode(PIN_SLIDE_POT_A, INPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);

  // Setup motor PWM using the working ESP32 API
  ledcAttach(ENA, pwmFreq, pwmResolution);
  ledcWrite(ENA, motorSpeed);
  
  // Start stopped
  stopMotor();

  Serial.println("System Ready. Type 'up' or 'down' in the Serial Monitor.");
}

void loop() {
  // Read and print the slide pot value
  int value_slide_pot_a = analogRead(PIN_SLIDE_POT_A);
  Serial.print("Slide Pot value: ");
  Serial.println(value_slide_pot_a);
  
  // Check for commands typed into the Serial Monitor
  if (Serial.available()) {
    command = Serial.readStringUntil('\n');
    command.trim(); // Removes invisible characters like \r

    if (command.equalsIgnoreCase("up")) {
      moveForward();
    }
    else if (command.equalsIgnoreCase("down")) {
      moveBackward();
    }
  }
  
  // Brief delay to prevent flooding the Serial Monitor
  delay(50); 
}

// =============================
// Motor Functions
// =============================
void moveForward() {
  Serial.println("Moving Forward for 250ms...");
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  delay(250);
  stopMotor();
}

void moveBackward() {
  Serial.println("Moving Backward for 250ms...");
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  delay(250);
  stopMotor();
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
}