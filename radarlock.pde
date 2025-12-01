// Radar visual untuk Processing (menerima data dari Arduino)
// Format data dari Arduino (disarankan): MODE,ANGLE,DISTANCE\n
//   MODE: single char: 'S' (SEARCH), 'V' (VERIFY), 'T' (TRACK sample), 'L' (LOCK)
// Contoh: "S,90,35\n"  atau "L,72,12\n"
// Kode juga kompatibel dengan format lama: "90,35\n" (diperlakukan sebagai SEARCH).

import processing.serial.*;

// --- Variabel Global ---
Serial serialPort;
PFont font;

// Window & radar
int screenWidth = 900;
int screenHeight = 520;
float radarRadius = 360;
float radarCenterX = screenWidth / 2.0;
float radarCenterY = screenHeight - 80;

// Data terakhir
int currentAngle = 0;
int currentDistance = 0;
char currentMode = 'S'; // default

// Histories
ArrayList<HistoryPoint> pointHistory = new ArrayList<HistoryPoint>();  // SEARCH/LOCK points (merah pudar)
ArrayList<HistoryPoint> trackHistory = new ArrayList<HistoryPoint>();  // TRACK samples (cyan)
ArrayList<HistoryPoint> verifyHistory = new ArrayList<HistoryPoint>(); // VERIFY samples (kuning)

// LOCK info (persistent highlight until timeout)
boolean lockedActive = false;
int lockedAngle = -1;
int lockedDistance = -1;
int lastLockSeenMillis = 0;
int LOCK_TIMEOUT_MS = 2000; // bila tidak ada update LOCK selama 2s => unlock

void settings() {
  size(screenWidth, screenHeight);
  smooth();
}

void setup() {
  font = createFont("Monospaced", 16);
  textFont(font);

  // Ganti port sesuai kebutuhan (cek Tools > Port di Arduino IDE)
  String portName = "COM5";  // <-- UBAH SESUAI PORT ARDUINO
  try {
    println("Connecting to " + portName + " ...");
    serialPort = new Serial(this, portName, 9600);
    serialPort.clear();
    serialPort.bufferUntil('\n');
  } catch (Exception e) {
    println("Serial port error: " + e.getMessage());
    println("Check port name and close Serial Monitor in Arduino IDE.");
    exit();
  }

  background(0);
}

void draw() {
  background(0, 18, 0);

  drawRadarGrid();
  drawLegendAndInfo();
  drawSweepLine(currentAngle);
  drawLockedTarget();
  drawDetectedPoints(); // gambar titik dari data "live"
  drawHistories();      // gambar history pudar
  cleanupHistories();
  checkLockTimeout();
}

// ====================== Drawing helpers ======================

void drawRadarGrid() {
  strokeWeight(2);
  stroke(0, 140, 0);
  noFill();

  // concentric arcs
  for (int i = 1; i <= 3; i++) {
    float r = i * (radarRadius / 3.0);
    arc(radarCenterX, radarCenterY, r*2, r*2, PI, TWO_PI);
  }

  // baseline
  line(radarCenterX - radarRadius, radarCenterY,
       radarCenterX + radarRadius, radarCenterY);

  // radial spokes
  stroke(0, 120, 0, 140);
  for (int i = 0; i < 9; i++) {
    float ang = PI + radians(i * 22.5f);
    float x2 = radarCenterX + radarRadius * cos(ang);
    float y2 = radarCenterY + radarRadius * sin(ang);
    line(radarCenterX, radarCenterY, x2, y2);
  }
}

// Info box kiri atas + legend bawah
void drawLegendAndInfo() {
  // mode box
  String modeStr = modeName(currentMode);
  int modeColor = modeColorFor(currentMode);

  fill(0, 180);
  noStroke();
  rect(12, 12, 260, 100, 8);

  fill(modeColor);
  textAlign(LEFT, TOP);
  text("Mode: " + modeStr, 20, 18);

  fill(200);
  text("Angle: " + currentAngle + "°", 20, 44);
  text("Distance: " + currentDistance + " cm", 20, 68);
  text("Locked: " + (lockedActive ? "YES" : "NO"), 20, 92);

  // legend
  float lx = 20;
  float ly = height - 120;
  fill(0, 180);
  rect(lx - 8, ly - 12, 300, 130, 8);

  // SEARCH points (faded red)
  stroke(255, 60, 60);
  strokeWeight(6);
  point(lx + 10, ly + 6);
  fill(200);
  noStroke();
  text("Search/Detect point", lx + 30, ly - 10);

  // VERIFY (yellow)
  stroke(255, 200, 0);
  strokeWeight(6);
  point(lx + 10, ly + 36);
  fill(200);
  noStroke();
  text("Verify samples", lx + 30, ly + 28);

  // TRACK samples (cyan)
  stroke(0, 200, 200);
  strokeWeight(6);
  point(lx + 10, ly + 66);
  fill(200);
  noStroke();
  text("Track samples", lx + 30, ly + 58);

  // LOCK target (big red)
  fill(255, 80, 80);
  noStroke();
  ellipse(lx + 10, ly + 96, 8, 8);
  fill(200);
  text("Locked target (persistent)", lx + 30, ly + 88);
}

// sweep line radar
void drawSweepLine(int angle) {
  stroke(0, 220, 0, 140);
  strokeWeight(3);
  float radAngle = radians(angle + 180); // mirror for display
  float endX = radarCenterX + radarRadius * cos(radAngle);
  float endY = radarCenterY + radarRadius * sin(radAngle);
  line(radarCenterX, radarCenterY, endX, endY);
}

// gambar titik deteksi "live" + masukkan ke history
void drawDetectedPoints() {
  float maxDist = 50.0f;
  if (currentDistance > 0 && currentDistance <= maxDist) {
    float mappedDist = map(currentDistance, 0, maxDist, 0, radarRadius);
    float radAngle = radians(currentAngle + 180);
    float px = radarCenterX + mappedDist * cos(radAngle);
    float py = radarCenterY + mappedDist * sin(radAngle);

    switch(currentMode) {
    case 'S': // SEARCH detection -> faded red
      stroke(255, 60, 60);
      strokeWeight(6);
      point(px, py);
      pointHistory.add(new HistoryPoint(px, py, 255, color(255, 60, 60)));
      break;

    case 'V': // VERIFY sample -> yellow
      stroke(255, 200, 0);
      strokeWeight(7);
      point(px, py);
      verifyHistory.add(new HistoryPoint(px, py, 220, color(255, 200, 0)));
      break;

    case 'T': // TRACK sample -> cyan
      stroke(0, 200, 200);
      strokeWeight(6);
      point(px, py);
      trackHistory.add(new HistoryPoint(px, py, 255, color(0, 200, 200)));
      break;

    case 'L': // LOCK update
      lockedActive = true;
      lockedAngle = currentAngle;
      lockedDistance = currentDistance;
      lastLockSeenMillis = millis();

      stroke(255, 30, 30);
      strokeWeight(8);
      point(px, py);

      // simpan ke history juga
      pointHistory.add(new HistoryPoint(px, py, 180, color(255, 30, 30)));
      break;

    default:
      stroke(200);
      strokeWeight(5);
      point(px, py);
    }
  }
}

// gambar target LOCK (persistent, dengan efek pulsa)
void drawLockedTarget() {
  if (!lockedActive) return;

  float maxDist = 50.0f;
  float mappedDist = map(lockedDistance, 0, maxDist, 0, radarRadius);
  float radAngle = radians(lockedAngle + 180);
  float px = radarCenterX + mappedDist * cos(radAngle);
  float py = radarCenterY + mappedDist * sin(radAngle);

  float t = (millis() % 1000) / 1000.0f;
  float pulse = 1.0f + 0.4f * sin(TWO_PI * t);

  noStroke();
  fill(255, 30, 30, 160);
  ellipse(px, py, 18 * pulse, 18 * pulse);

  stroke(255, 80, 80);
  strokeWeight(2);
  noFill();
  ellipse(px, py, 34 * pulse, 34 * pulse);

  stroke(255, 120, 120);
  strokeWeight(1.5f);
  line(px - 16, py, px + 16, py);
  line(px, py - 16, px, py + 16);
}

// gambar history yang memudar
void drawHistories() {
  // TRACK samples
  for (HistoryPoint p : trackHistory) {
    stroke(red(p.c), green(p.c), blue(p.c), p.age);
    strokeWeight(5);
    point(p.x, p.y);
  }

  // VERIFY samples
  for (HistoryPoint p : verifyHistory) {
    stroke(red(p.c), green(p.c), blue(p.c), p.age);
    strokeWeight(6);
    point(p.x, p.y);
  }

  // SEARCH / LOCK samples
  for (HistoryPoint p : pointHistory) {
    stroke(red(p.c), green(p.c), blue(p.c), p.age);
    strokeWeight(4);
    point(p.x, p.y);
  }
}

// fade & clean history lists
void cleanupHistories() {
  ArrayList<HistoryPoint> newPH = new ArrayList<HistoryPoint>();
  for (HistoryPoint p : pointHistory) {
    p.age -= 2;
    if (p.age > 0) newPH.add(p);
  }
  pointHistory = newPH;

  ArrayList<HistoryPoint> newTH = new ArrayList<HistoryPoint>();
  for (HistoryPoint p : trackHistory) {
    p.age -= 6;
    if (p.age > 0) newTH.add(p);
  }
  trackHistory = newTH;

  ArrayList<HistoryPoint> newVH = new ArrayList<HistoryPoint>();
  for (HistoryPoint p : verifyHistory) {
    p.age -= 10;
    if (p.age > 0) newVH.add(p);
  }
  verifyHistory = newVH;

  // hard cap ukuran list biar gak kebanyakan
  while (pointHistory.size() > 600) {
    pointHistory.remove(0);
  }
  while (trackHistory.size() > 120) {
    trackHistory.remove(0);
  }
  while (verifyHistory.size() > 80) {
    verifyHistory.remove(0);
  }
}

// auto-unlock jika tidak ada update LOCK dalam LOCK_TIMEOUT_MS
void checkLockTimeout() {
  if (!lockedActive) return;
  if (millis() - lastLockSeenMillis > LOCK_TIMEOUT_MS) {
    lockedActive = false;
    println("LOCK timed out -> unlocked");
  }
}

// ====================== Serial parsing ======================

void serialEvent(Serial port) {
  String raw = port.readStringUntil('\n');
  if (raw == null) return;
  raw = trim(raw);
  if (raw.length() == 0) return;

  // coba split dengan koma
  String[] parts = split(raw, ',');
  try {
    if (parts.length == 3 && parts[0].length() == 1) {
      // Format baru: MODE,ANGLE,DIST
      char modeChar = parts[0].charAt(0);
      int angle = Integer.parseInt(trim(parts[1]));
      int dist = Integer.parseInt(trim(parts[2]));

      currentMode = modeChar;
      currentAngle = constrain(180 - angle, 0, 180);
      currentDistance = dist;

      // Tambahan: jika Arduino kirim "S,0,0" saat stop -> treat as parked
      if (modeChar == 'S' && angle == 0 && dist == 0) {
        // sweep line di 0 derajat (sudah otomatis dari currentAngle),
        // matikan lock
        lockedActive = false;
        // optional: bersihkan history total (kalau mau efek reset langsung)
        // pointHistory.clear();
        // trackHistory.clear();
        // verifyHistory.clear();
        println("Radar PARKED at 0° (S,0,0 received)");
      }

    } else if (parts.length == 2) {
      // Legacy: ANGLE,DIST -> treat as SEARCH sample
      currentMode = 'S';
      int angle = Integer.parseInt(trim(parts[0]));
      int dist = Integer.parseInt(trim(parts[1]));
      currentAngle = constrain(180 - angle, 0, 180);
      currentDistance = dist;

    } else {
      // Bukan format data radar, bisa jadi log dari Serial.println()
      println("Unknown serial format: " + raw);
    }
  }
  catch (NumberFormatException e) {
    println("Parse error: " + raw);
  }
}

// ====================== Utilities ======================

String modeName(char m) {
  switch(m) {
  case 'S': return "SEARCH";
  case 'V': return "VERIFY";
  case 'T': return "TRACK";
  case 'L': return "LOCK";
  default:  return "UNKNOWN";
  }
}

int modeColorFor(char m) {
  switch(m) {
  case 'S': return color(0, 220, 0);
  case 'V': return color(255, 200, 0);
  case 'T': return color(0, 200, 200);
  case 'L': return color(255, 80, 80);
  default:  return color(200);
  }
}

// ====================== Helper class ======================

class HistoryPoint {
  float x, y;
  float age;
  int c;

  HistoryPoint(float x, float y, float age, int c) {
    this.x = x;
    this.y = y;
    this.age = age;
    this.c = c;
  }
}
