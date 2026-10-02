#pragma once

#include <Arduino.h>
#include <string>
#include <vector>

#include "../config.h"
#include "../core/packet.h"
#include "../core/router.h"
#include "../ble/ble_server.h"
#include "../ble/ble_mesh.h"
#include "../link/lora_link.h"

#ifndef ST_ENGINE_NAME
#define ST_ENGINE_NAME "RelayEngine"
#endif

#include <functional>

// --------------------------------------------------------------------------
// RelayEngine — single application core used by every firmware variant.
//
// Receive path: LoRa RX flag / BLE write / (gateway) host serial → Router →
// execute actions (DELIVER / LORA_TX / BLE_TX). Also emits periodic STATUS
// heartbeats so LoRa & mesh peers know the node is alive.
// --------------------------------------------------------------------------
class RelayEngine {
 public:
  RelayEngine();

  LoRaLink lora;
  BleServer ble;
  BleMesh mesh;
  st::Router router;

  // Optional sink for packets that terminate at THIS node (gateway build).
  // Called with the codec JSON, a human label, and `persist` (false for
  // liveness-only STATUS heartbeats). Used to feed the embedded web hub and
  // flash log. Invoked from the main loop (never from ISR/BLE task).
  std::function<void(const std::string& json, const char* via, bool persist)> onDeliver;

  bool begin();
  void run();

  // BLE (peripheral) inbound — called from the NimBLE task; queue for loop.
  void queueInboundJson(const std::string& json, uint16_t handle);

  // Host serial (gateway) inbound commands.
  void handleHostLine(const std::string& line);

  void handlePacket(st::Packet p, const std::string& device);

  // static router hook
  static bool clientAttached(const std::string& dst, void* ctx);

  // Physical SOS button on relay nodes (config.h ST_SOS_BUTTON_GPIO).
  void triggerSos();

 private:
  struct Inbound {
    Inbound() = default;
    Inbound(const std::string& j, uint16_t h) : json(j), handle(h) {}
    std::string json;
    uint16_t handle = 0;
  };
  std::vector<Inbound> inboundBuf_;
  portMUX_TYPE mux_ = portMUX_INITIALIZER_UNLOCKED;

  void processDecision(st::Packet& p, const st::RouteDecision& d, const std::string& device);
  void sendStatus();
  std::string statusBody();
  void serviceButton(uint32_t nowMs);
  void startAlarm(const char* why, const st::Packet& p);
  void driveAlarm(uint32_t nowMs);
  void pulseRx();
  void pulseTx();
  void serviceLeds(uint32_t nowMs);
  void setLedPin(uint8_t pin, bool on);
  bool tryAdoptTime(const st::Packet& p, uint32_t nowMs);

  uint32_t bootMs_ = 0;
  uint32_t lastStatusMs_ = 0;
  uint32_t lastPruneMs_ = 0;
  uint32_t lastAdvMs_ = 0;
  uint32_t ledPhaseEndMs_ = 0;
  uint32_t alarmEndMs_ = 0;
  uint32_t lastSyncMs_ = 0;
  uint8_t ledRepeatsLeft_ = 0;
  uint8_t activeLedPin_ = 0xFF;   // 0xFF = nothing lit
  bool ledOn_ = false;
  bool txBurstActive_ = false;
  uint32_t txBurstStartMs_ = 0;
  bool btnPrevPressed_ = false;
  uint32_t btnLastMs_ = 0;
  uint32_t statusPushAtMs_ = 0;
};