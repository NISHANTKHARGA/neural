#pragma once

#include <Arduino.h>
#include <deque>
#include <map>
#include <mutex>
#include <string>

#include <NimBLEDevice.h>

#include "../config.h"

// --------------------------------------------------------------------------
// BleMesh — ESP32 central (GATT client).
//
// Relays communicate ONLY through explicit application-level forwarding.
// A relay with a packet to push connects (as a central) to a neighbouring
// SAFETRAILS relay's peripheral and writes the JSON packet to its SOS_TX
// characteristic. Neighbour discovery uses periodic BLE scans.
// --------------------------------------------------------------------------
class BleMesh {
 public:
  void begin();
  void maintain(long long nowMs);

  // Schedule a JSON packet for delivery into the BLE mesh.
  void enqueue(std::string json);

  size_t queueSize() const { return queue_.size(); }
  int peerCount() const { return (int)peers_.size(); }
  std::string peerSummary();

 private:
  struct Peer {
    NimBLEAddress addr;
    int8_t rssi = -127;
    uint32_t lastSeenMs = 0;
    // Connection backoff. A phone that advertises SAFETRAILS_RELAY but refuses
    // GATT connections (or is busy as its own central) used to be retried every
    // flush cooldown, so a single uncooperative peer filled the console with
    // "Connection failed" errors forever and starved the real mesh.
    uint8_t fails = 0;
    uint32_t failUntilMs = 0;
  };

  void scanNow();
  bool flushOne();
  NimBLEAddress pickPeer() const;

  mutable std::mutex mutex_;
  std::deque<std::string> queue_;
  std::map<std::string, Peer> peers_;
  NimBLEClient* client_ = nullptr;
  bool clientBusy_ = false;
  uint32_t lastScanMs_ = 0;
  uint32_t lastFlushMs_ = 0;
};