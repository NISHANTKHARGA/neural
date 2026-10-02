// SAFETRAILS — BLE-only demo relay (NO LoRa radio strapped).
//
// Proves the application-level multi-hop requirement: packets are received
// from a phone over BLE, validated, de-duplicated, TTL-decremented, then
// forwarded over BLE to the next SAFETRAILS relay until a LoRa-capable node
// takes over. No radio involvement at all.
#include "relay_engine.h"

RelayEngine engine;

void setup() {
  if (!engine.begin()) {  // ST_HAS_LORA=0 → lora.begin() fails gracefully
    while (1) delay(1000);
  }
  Serial.println("[demo_relay] BLE-only store-and-forward relay ready");
}

void loop() {
  engine.run();
  delay(1);
}