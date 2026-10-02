// SAFETRAILS — Traveler-facing relay node. ESP32 + SX1278 LoRa + dual-role BLE.
// Receives SOS/RESCUE/BROAD over BLE, forwards via LoRa when a gateway is
// reachable, otherwise handoffs through the BLE mesh (application-level).
#include "relay_engine.h"

RelayEngine engine;

void setup() {
  if (!engine.begin()) {
    while (1) {
      delay(1000);
      Serial.println("[relay] init failure");
    }
  }
  Serial.println("[relay] READY — press to test: open serial, send JSON or rely on status.");
}

void loop() {
  engine.run();
  delay(1);
}