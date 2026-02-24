#define PIN_SLIDE_POT_A A0
#define RIGHT_RANGE 900 // not sure if this is how you define something
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
  int poten_read = analogRead(PIN_SLIDE_POT_A);
  Serial.print("Slide Pot value: ");
  Serial.println(poten_read);

  if (poten_read < 500){ //make sure this
      moveForward(); 
    }

    if (poten_read > 600){
      moveBackward();
    }

  if (turn_right){
    //have to move motor to upper range
    
  }
  if (straight){
    //have to move motor to middle range
    if (poten_read < RIGHT_RANGE){
        
    }

  }

  if(turn_left){
    //have to move motor to left range

  }
  
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
  delay(25);
  stopMotor();
}

void moveBackward() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  delay(25);
  stopMotor();
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
}