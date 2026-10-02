#pragma once

#include <Arduino.h>
#include <functional>
#include <map>
#include <string>

#include <NimBLEDevice.h>

#include "../core/packet.h"

// SAFETRAILS BLE service — UUIDs per shared/protocol/PROTOCOL.md §3.
#define ST_SVC_UUID "2f32f800-6a00-4f6a-9a5e-001122334455"
#define ST_SOS_TX   "2f32f801-6a00-4f6a-9a5e-001122334455"
#define ST_SOS_RX   "2f32f802-6a00-4f6a-9a5e-001122334455"
#define ST_ACL_TX   "2f32f803-6a00-4f6a-9a5e-001122334455"
#define ST_RES_RX   "2f32f804-6a00-4f6a-9a5e-001122334455"
#define ST_BRDC_RX  "2f32f805-6a00-4f6a-9a5e-001122334455"
#define ST_STAT_RX  "2f32f806-6a00-4f6a-9a5e-001122334455"
#define ST_DATA_RX  "2f32f807-6a00-4f6a-9a5e-001122334455"

// --------------------------------------------------------------------------
// BleServer — ESP32 peripheral (GATT server).
//
//  * advertises as SAFETRAILS_RELAY
//  * accepts JSON packets on SOS_TX / ACL_TX (phones AND peer relays write
//    here), routes them to `onPacket` for the relay engine
//  * pushes packets down to attached phones on type-specific notify channels
//  * tracks which tourist id ↔ BLE connection is attached so the router can
//    treat unicast packets to that tourist as local deliveries
// --------------------------------------------------------------------------
class BleServer {
 public:
  // Called with the raw JSON that arrived on a write characteristic.
  std::function<void(const std::string&)> onInbound = nullptr;

  // Called from the NimBLE connect callback; relay loop polls consumeConnectPulse().
  void noteConnect() { connectPulse_ = true; }
  bool consumeConnectPulse() {
    const bool p = connectPulse_;
    connectPulse_ = false;
    return p;
  }

  // Called from the NimBLE disconnect callback (NimBLE task context, so it must
  // not touch clients_). The handle is parked in a tiny lock-free ring that the
  // relay loop drains via pruneDroppedClients().
  void noteDisconnect(uint16_t handle) {
    if (handle == 0 || handle == 0xFFFF) return;
    dropped_[droppedAt_ % kDroppedRing] = handle;
    ++droppedAt_;
  }

  // Drop registry entries whose BLE link is gone. Without this a phone that
  // disconnects (app closed, node switch, out of range) keeps counting as
  // "attached" for the whole link TTL, and the router then treats a unicast to
  // that tourist as locally delivered -- printing it to the serial log while
  // notifying nobody and never forwarding it over LoRa.
  void pruneDroppedClients();

  // Keep "attached" true for as long as the BLE link is actually up. The phone
  // only writes when it sends an SOS/ACK, so without this an idle-but-connected
  // client would age out of the registry (ST_MESH_PEER_TTL_MS) and the router
  // would stop delivering its unicast packets to it.
  void refreshClientLiveness();

  bool begin(const char* nodeId);
  void stopAdv() { NimBLEDevice::stopAdvertising(); }
  void startAdv();
  // Re-start advertising if a client was connected and we lost the link but
  // the disconnect event did not re-advertise (see NimBLE advertiseOnDisconnect).
  void ensureAdv();
  // True when the radio is broadcasting connectable advertisements AND the
  // payload was actually programmed (both checked by the NimBLE library).
  bool isAdvertising() const {
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    return adv != nullptr && adv->isAdvertising();
  }

  // Push a packet to every subscribed phone client (JSON selection by type).
  void notifyPacket(const st::Packet& p);

  // Remember that `touristId` is attached to `handle`.
  void linkClient(const std::string& touristId, uint16_t handle);

  // Router hook: is dst id attached to this node (within link TTL)?
  bool hasClient(const std::string& dst, long long nowMs);
  std::string peerSummary();

 private:
  NimBLEServer* server_ = nullptr;
  NimBLECharacteristic* sosRx_ = nullptr;
  NimBLECharacteristic* rescueRx_ = nullptr;
  NimBLECharacteristic* broadRx_ = nullptr;
  NimBLECharacteristic* statRx_ = nullptr;
  NimBLECharacteristic* dataRx_ = nullptr;

  struct Client {
    std::string touristId;
    uint32_t lastSeenMs = 0;
  };
  std::map<uint16_t, Client> clients_;
  volatile bool connectPulse_ = false;

  static constexpr size_t kDroppedRing = 4;
  volatile uint16_t dropped_[kDroppedRing] = {0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF};
  volatile uint32_t droppedAt_ = 0;
};