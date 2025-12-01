#include <Servo.h>

// --- Pin Definitions ---
const int SERVO_PIN = 11;
const int TRIG_PIN = 13;
const int ECHO_PIN = 12;
const int SOUND_PIN = 2;        // digital output dari modul sound (DO) -> gunakan pin interrupt
const int BUTTON_PIN = 0;       // tombol start/stop (CATATAN di bawah)
 
// --- Sound active level (ubah jika modul DO aktif LOW) ---
const int SOUND_ACTIVE_LEVEL = HIGH; // set to HIGH atau LOW sesuai modulmu

// --- Constants for Servo ---
const int MIN_ANGLE = 0;
const int MAX_ANGLE = 180;
const int ANGLE_STEP = 2;        // langkah sweep saat SEARCH
const int SWEEP_DELAY = 30;      // delay antar langkah (ms)

// --- Constants for Ultrasonic Sensor ---
const float SOUND_SPEED_FACTOR = 58.2;
const int MAX_CM_DISTANCE = 50;  // batas maks deteksi 50cm

// --- Locking / Verification parameters (tuning) ---
const int DETECT_THRESHOLD = 40;       // jika jarak <= ini dianggap deteksi kandidat (cm)
const int VERIFY_SAMPLES = 5;          // ambil sejumlah sample saat verifikasi
const int VERIFY_REQUIRED = 3;         // harus >= ini samples valid agar yakin bukan noise
const int VERIFY_DELAY_MS = 40;        // delay antar sample saat verifikasi
const int TRACK_WINDOW = 8;            // ± derajat untuk mencari posisi terbaik saat lock
const int TRACK_STEP = 2;              // step saat tracking mencari posisi terbaik
const int LOCK_LOST_THRESHOLD = 3;     // berapa kali berturut-turut tidak terdeteksi => lost

// --- Sound trigger parameters ---
const unsigned long SOUND_DEBOUNCE_MS = 350; // minimal ms antara trigger suara (debounce)
const unsigned long BUTTON_DEBOUNCE_MS = 250; // debounce tombol (start)
const int ROTATIONS_TO_GIVE_UP = 1; // jumlah rotasi penuh tanpa deteksi -> kembali wait sound

Servo myServo;

// state machine
enum State { WAIT_SOUND, SEARCH, VERIFY, LOCK };
State state = WAIT_SOUND;

// sweep variables
int sweepAngle = MIN_ANGLE;
int sweepDir = 1; // 1 naik, -1 turun

// candidate / lock variables
int candidateAngle = -1;
int candidateDistance = 0;
int lockAngle = -1;
int lockDistance = 0;
int lockLostCount = 0;

// rotation / detection tracking
int rotationsWithoutDetection = 0;    // jumlah rotasi penuh berturut-turut tanpa deteksi
bool detectionDuringRotation = false; // apakah ada deteksi selama rotasi berjalan

// sound detection flag (set oleh ISR, digunakan & debounced di loop)
volatile bool soundISRflag = false;
unsigned long lastSoundMillis = 0;

// button handling
unsigned long lastButtonPress = 0;
bool lastButtonState = HIGH;

void setup() {
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(SOUND_PIN, INPUT);

  // Tombol: INPUT_PULLUP (satu kaki tombol ke pin 0, kaki lainnya ke GND)
  pinMode(BUTTON_PIN, INPUT_PULLUP);

  // Interrupt untuk suara
  if (SOUND_ACTIVE_LEVEL == HIGH) {
    attachInterrupt(digitalPinToInterrupt(SOUND_PIN), soundISR, RISING);
  } else {
    attachInterrupt(digitalPinToInterrupt(SOUND_PIN), soundISR, FALLING);
  }

  myServo.attach(SERVO_PIN);
  Serial.begin(9600);

  // awal: park servo pada MIN_ANGLE
  sweepAngle = MIN_ANGLE;
  sweepDir = 1;
  myServo.write(sweepAngle);
  delay(200);

  state = WAIT_SOUND;
  lastSoundMillis = millis(); // inisialisasi supaya debounce tidak terpanggil segera
  Serial.println("READY - Idle, waiting for loud sound (clap) or button...");
}

// ---------------------------------
// ISR suara: singkat! hanya set flag
// ---------------------------------
void soundISR() {
  soundISRflag = true;
}

// ---------------------------
// Fungsi cek tombol dengan debounce proper
// ---------------------------
bool checkButton() {
  bool currentButtonState = digitalRead(BUTTON_PIN);
  
  // Deteksi transisi dari HIGH ke LOW (tombol ditekan)
  if (lastButtonState == HIGH && currentButtonState == LOW) {
    unsigned long now = millis();
    if (now - lastButtonPress > BUTTON_DEBOUNCE_MS) {
      lastButtonPress = now;
      lastButtonState = currentButtonState;
      return true; // tombol baru ditekan
    }
  }
  
  lastButtonState = currentButtonState;
  return false;
}

// main loop
void loop() {
  // Cek tombol - SELALU dicek terlepas dari state
  if (checkButton()) {
    if (state == WAIT_SOUND) {
      // START radar
      Serial.println("BUTTON PRESSED -> starting radar");
      beginRadar();
    } else {
      // STOP radar (dari state manapun)
      Serial.println("BUTTON PRESSED -> STOP RADAR, back to WAIT_SOUND");
      stopRadar();
    }
  }

  // Jika state WAIT_SOUND: cek flag ISR & lakukan debounce di sini
  if (state == WAIT_SOUND) {
    if (soundISRflag) {
      soundISRflag = false; // reset segera
      unsigned long now = millis();
      if (now - lastSoundMillis > SOUND_DEBOUNCE_MS) {
        lastSoundMillis = now;
        Serial.println("SOUND TRIGGERED (debounced) - starting radar");
        beginRadar();
      }
    }
    // tetap di idle
    return;
  }

  // jalankan state machine radar
  switch(state) {
    case SEARCH:
      searchStep();
      break;
    case VERIFY:
      verifyCandidate();
      break;
    case LOCK:
      lockStep();
      break;
    default:
      // fallback safety
      stopRadar();
      break;
  }
}

// fungsi untuk memulai radar: reset variabel, set state
void beginRadar() {
  rotationsWithoutDetection = 0;
  detectionDuringRotation = false;
  candidateAngle = -1;
  candidateDistance = 0;
  lockAngle = -1;
  lockDistance = 0;
  lockLostCount = 0;

  // park & start sweep
  sweepAngle = MIN_ANGLE;
  sweepDir = 1;
  myServo.write(sweepAngle);
  delay(200);
  
  state = SEARCH;
  Serial.println("Radar STARTED");
}

// fungsi untuk stop radar dan kembali ke idle
void stopRadar() {
  // Kembalikan servo ke posisi 0
  myServo.write(MIN_ANGLE);
  delay(200);
  
  state = WAIT_SOUND;
  
  // reset semua variabel
  rotationsWithoutDetection = 0;
  detectionDuringRotation = false;
  candidateAngle = -1;
  candidateDistance = 0;
  lockAngle = -1;
  lockDistance = 0;
  lockLostCount = 0;
  sweepAngle = MIN_ANGLE;
  sweepDir = 1;
  
  Serial.println("Radar STOPPED - back to WAIT_SOUND");
}

// SEARCH: sapu dan cek tiap sudut
void searchStep() {
  myServo.write(sweepAngle);
  delay(SWEEP_DELAY);

  int dist = calculateDistance();
  printData('S', sweepAngle, dist);

  // treat 0 (timeout) as no detection
  if (dist > 0 && dist <= DETECT_THRESHOLD) {
    candidateAngle = sweepAngle;
    candidateDistance = dist;
    detectionDuringRotation = true; // ada deteksi di rotasi ini
    state = VERIFY;
    return;
  }

  // advance sweep
  sweepAngle += sweepDir * ANGLE_STEP;

  // boundary checks -> potential direction change (and possibly full rotation completion)
  bool justCompletedFullRotation = false;
  if (sweepAngle >= MAX_ANGLE) {
    sweepAngle = MAX_ANGLE;
    sweepDir = -1;
  } else if (sweepAngle <= MIN_ANGLE) {
    sweepAngle = MIN_ANGLE;
    sweepDir = 1;
    justCompletedFullRotation = true;
  }

  // jika rotasi selesai -> increment rotationsWithoutDetection jika tidak ada deteksi selama rotasi
  if (justCompletedFullRotation) {
    if (!detectionDuringRotation) {
      rotationsWithoutDetection++;
      Serial.print("Rotation completed with NO detection. Count=");
      Serial.println(rotationsWithoutDetection);
    } else {
      rotationsWithoutDetection = 0;
      Serial.println("Rotation completed WITH detection -> counter reset");
    }
    detectionDuringRotation = false;

    if (rotationsWithoutDetection >= ROTATIONS_TO_GIVE_UP) {
      Serial.println("No detection after several rotations -> returning to WAIT_SOUND");
      stopRadar();
      return;
    }
  }
}

// VERIFY: ambil beberapa sample untuk konfirmasi
void verifyCandidate() {
  myServo.write(candidateAngle);
  delay(80); // beri waktu servo sampai posisi

  int countGood = 0;
  int lastDist = 0;
  for (int i = 0; i < VERIFY_SAMPLES; ++i) {
    int d = calculateDistance();
    lastDist = d;
    if (d > 0 && d <= DETECT_THRESHOLD) countGood++;
    delay(VERIFY_DELAY_MS);
  }
  printData('V', candidateAngle, lastDist);

  if (countGood >= VERIFY_REQUIRED) {
    lockAngle = candidateAngle;
    lockDistance = lastDist;
    lockLostCount = 0;
    state = LOCK;
    Serial.println("LOCK ACQUIRED");
  } else {
    candidateAngle = -1;
    candidateDistance = 0;
    state = SEARCH;
    sweepAngle += sweepDir * ANGLE_STEP;
    if (sweepAngle < MIN_ANGLE) sweepAngle = MIN_ANGLE;
    if (sweepAngle > MAX_ANGLE) sweepAngle = MAX_ANGLE;
  }
}

// LOCK: track target by scanning small window around lockAngle
void lockStep() {
  int bestAngle = lockAngle;
  int bestDist = 10000;
  int startA = max(MIN_ANGLE, lockAngle - TRACK_WINDOW);
  int endA   = min(MAX_ANGLE, lockAngle + TRACK_WINDOW);
  for (int a = startA; a <= endA; a += TRACK_STEP) {
    myServo.write(a);
    delay(SWEEP_DELAY);

    int d = calculateDistance();
    printData('T', a, d); // T = track sample
    if (d > 0 && d < bestDist) {
      bestDist = d;
      bestAngle = a;
    }
  }

  // decide result of tracking sweep
  if (bestDist <= DETECT_THRESHOLD && bestDist > 0) {
    lockAngle = bestAngle;
    lockDistance = bestDist;
    lockLostCount = 0;
    myServo.write(lockAngle);
    delay(SWEEP_DELAY);
    printData('L', lockAngle, lockDistance); // L = locked position
    detectionDuringRotation = true;
  } else {
    lockLostCount++;
    Serial.print("LOCK_MISS ");
    Serial.println(lockLostCount);
    if (lockLostCount >= LOCK_LOST_THRESHOLD) {
      Serial.println("LOCK LOST -> resuming SEARCH");
      lockAngle = -1;
      lockDistance = 0;
      candidateAngle = -1;
      state = SEARCH;
      int cur = constrain(myServo.read(), MIN_ANGLE, MAX_ANGLE);
      sweepAngle = cur;
    } else {
      delay(100);
    }
  }
}

// measure distance (cm) with timeout
int calculateDistance() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  long duration = pulseIn(ECHO_PIN, HIGH, 10000); // 10 ms timeout
  if (duration == 0) return 0;
  int cm = (int)(duration / SOUND_SPEED_FACTOR);
  if (cm > MAX_CM_DISTANCE) return MAX_CM_DISTANCE;
  return cm;
}

// print data to serial (state char, angle, distance)
void printData(char mode, int angle, int distance) {
  Serial.print(mode);
  Serial.print(",");
  Serial.print(angle);
  Serial.print(",");
  Serial.println(distance);
}
