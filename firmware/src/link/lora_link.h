#pragma once

#include <Arduino.h>
#include <string>

#if ST_HAS_LORA
#include <RadioLib.h>
#endif

#include "../config.h"

// --------------------------------------------------------------------------
// LoRaLink — SX1278/RA-02 radio via SPI2/VSPI (RadioLib).
// All radio parameters come from config.h so regional compliance is a
// configuration decision, not a hardcoded assumption.
// --------------------------------------------------------------------------
class LoRaLink {
 public:
  // Callback trampoline (set in begin()).
  static LoRaLink* s_self;

  bool begin();

  // Returns true and fills `frame` with one received compact LoRa frame.
  // Non-blocking poll driven from the main loop.
  bool pollReceive(std::string& frame);

  // Blocking transmit of a compact frame (radio CRC enabled).
  bool send(const std::string& compact);

  float lastRssi() const { return lastRssi_; }
  float lastSnr() const { return lastSnr_; }
  bool up() const { return up_; }
  bool hasActivity() const {
    return up_ && (millis() - lastRxMs_ < ST_LORA_REACHABLE_WINDOW_MS);
  }

  void setPending() { pending_ = true; }

 private:
#if ST_HAS_LORA
  Module module_ = Module(ST_LORA_CS, ST_LORA_DIO0, ST_LORA_RST, ST_LORA_DIO1);
  SX1278 radio_ = SX1278(&module_);
#endif
  bool up_ = false;
  volatile bool pending_ = false;
  uint32_t lastRxMs_ = 0;
  float lastRssi_ = -127.0f;
  float lastSnr_ = 0.0f;
};