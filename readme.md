# Radar Lock

Ultrasonic + servo “radar” that is triggered by a loud sound (clap) or a push button, sweeps to search for an object with an HC-SR04 ultrasonic sensor, verifies the detection, then locks & tracks the nearest target. Serial telemetry is emitted for logging/plotting.

- Arduino sketch: `radar/radar.ino`  
- Processing visualization: `radarlock.pde` (open with Processing IDE).  
  - **Important:** You MUST update the `portName` inside `radarlock.pde` to match your Arduino serial port (e.g., `COM3`, `/dev/ttyACM0`, `/dev/ttyUSB0`, etc.).

---

## Quick summary / features

- Start radar with:
  - Loud sound (sound sensor / clap), or  
  - Push button (manual start/stop).
- Servo sweep: 0° → 180° scanning (configurable).  
- Candidate verification: multiple HC-SR04 samples to reduce false positives.  
- Lock & track: scan small window around locked angle to follow closest target.  
- UART telemetry: `MODE,ANGLE,DISTANCE` (CSV-like) for logging/plotting.  
  - MODE = `S` (Search), `V` (Verify), `T` (Track), `L` (Lock).

---

## Files in repo

- `radar/radar.ino` — Arduino sketch (main code).  
- `radar/radarlock.pde` — Processing visualization (serial plotter).  
- `README.md` — this file.  
- `requirements.txt` — optional Python deps for serial logging (`pyserial`).

---

## Wiring / Pinout

> **Important:** Connect all GND pins together (Arduino GND ↔ Servo GND ↔ HC-SR04 GND ↔ Sound sensor GND).

### Servo
- Servo signal → **D11** (`SERVO_PIN`)  
- Servo Vcc → **5V** (or external 5V supply)  
- Servo GND → **GND**

### Ultrasonic HC-SR04
- TRIG → **D13** (`TRIG_PIN`)  
- ECHO → **D12** (`ECHO_PIN`)  
- Vcc → **5V**  
- GND → **GND**

### Sound sensor (digital out)
- DO → **D2** (`SOUND_PIN`) — used with `attachInterrupt()`  
- Vcc → **5V**  
- GND → **GND**

> If the sound module DO is active LOW, change `SOUND_ACTIVE_LEVEL` in the sketch.

### Start/Stop Button (IMPORTANT)
- One leg → **BUTTON_PIN** (change default to a safe pin, see below)  
- Other leg → **GND**

**Warning:** The original sketch default sets:
```cpp
const int BUTTON_PIN = 0; // D0
