// SAFETRAILS — Rescue gateway. ESP32 + SX1278 LoRa + BLE + embedded web.
// Terminates RCUE-destined packets, ACKs SOS, ingests dashboard commands,
// and — fully standalone — hosts its own WiFi hotspot + dashboard + WS hub so
// it works on power alone (no PC needed). Serial JSON output is also kept for
// the optional PC/Node bridge.
#include "../config.h"
#include "../web/gateway_web.h"
#include "relay_engine.h"

RelayEngine engine;
GatewayWeb web;

void setup() {
  if (!engine.begin()) {
    while (1) {
      delay(1000);
      Serial.println("[gateway] init failure");
    }
  }
  Serial.println("[gateway] READY — standalone AP + JSON packets");

  web.onCommand = [](const std::string& line) { engine.handleHostLine(line); };
  engine.onDeliver = [](const std::string& json, const char*, bool persist) {
    web.onPacket(json, persist);
  };

  web.begin(ST_AP_SSID, ST_AP_PASS, ST_AP_CHANNEL, ST_WS_PORT);
}

void loop() {
  engine.run();
  web.loop();
  delay(1);
}