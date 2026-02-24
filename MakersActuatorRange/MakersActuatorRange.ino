#define PIN_SLIDE_POT_A A0
#define RIGHT_RANGE 900 //this is the right value it should turn to
#define RIGHT_LIMIT 1000 // this is extreme case (should never go past this)
#define LEFT_RANGE // this is the left value it should turn to
#define HI_MID_RANGE //top of mid range
#define LO_MID_RANGE //bottom of mid range

/*
LEFT_LIMIT
LEFT_RANGE
LO_MID_RANGE
HI_MID_RANGE
RIGHT_RANGE
RIGHT_LIMIT
*/

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
  
  if (turn_right){ //this signal comes from the CS team
    //have to move motor to upper range
    if (poten_read < RIGHT_RANGE){
      moveForward(); //not sure if this moves it the right direction
    }
    if (poten_read > RIGHT_LIMIT{
      moveBackward();
    }
    
  }
  if (straight){
    //have to move motor to middle range
    // should be between the 
    if (poten_read > HI_MID_RANGE){
      moveBackward();
    }
    if (poten_read < LO_MID_RANGE){
      moveForward();
    }

  }

  if(turn_left){
    //have to move motor to left range
    if (poten_read > LEFT_RANGE){
      moveBackward(); //not sure if this moves it the correct direction
    }
    if (poten_read < LEFT_LIMIT{
      moveForward();
    }

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

void moveForward() { //assume this is move right (not sure we need to test)
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  delay(250);
  stopMotor();
}

void moveBackward() { //asume this is move left
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  delay(250);
  stopMotor();
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
}