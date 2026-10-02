#include "lora_link.h"

#if ST_HAS_LORA

LoRaLink* LoRaLink::s_self = nullptr;

static void onLoraIrq() {
  if (LoRaLink::s_self) LoRaLink::s_self->setPending();
}

bool LoRaLink::begin() {
  // VSPI pins used by the SX1278: SCK/MISO/MOSI from config.h
  SPI.begin(ST_LORA_SCK, ST_LORA_MISO, ST_LORA_MOSI, ST_LORA_CS);

  int state = radio_.begin(ST_LORA_FREQ_MHZ, ST_LORA_BW_KHZ, ST_LORA_SF, ST_LORA_CR,
                           ST_LORA_SYNC_WORD, ST_LORA_PWR_DBM, ST_LORA_PREAMBLE, 0);
  if (state != RADIOLIB_ERR_NONE) {
    up_ = false;
    Serial.printf("[lora] init failed: %d\n", state);
    return false;
  }

  // LoRa packet mode with automatic gain; radio CRC on by default.
  radio_.setCRC(true);

  s_self = this;
  radio_.setDio0Action(onLoraIrq, RISING);
  up_ = true;
  radio_.startReceive();
  Serial.printf("[lora] up: freq=%.1fMHz bw=%.0fkhz sf=%d cr=4/%d sync=0x%02x pwr=%d\n",
                (double)ST_LORA_FREQ_MHZ, (double)ST_LORA_BW_KHZ, ST_LORA_SF, ST_LORA_CR,
                ST_LORA_SYNC_WORD, ST_LORA_PWR_DBM);
  return true;
}

bool LoRaLink::pollReceive(std::string& frame) {
  if (!up_ || !pending_) return false;
  pending_ = false;

  String raw;
  int state = radio_.readData(raw);
  lastRssi_ = radio_.getRSSI();
  lastSnr_ = radio_.getSNR();

  if (state == RADIOLIB_ERR_NONE) {
    lastRxMs_ = millis();
    frame.assign(raw.c_str());
    radio_.startReceive();
    return true;
  }

  // CRC mismatch / truncation: drop, but re-arm the receiver immediately.
  radio_.startReceive();
  return false;
}

bool LoRaLink::send(const std::string& compact) {
  if (!up_) return false;
  int state = radio_.transmit(compact.c_str());
  // Re-arm receive so a reply in flight is not missed.
  radio_.startReceive();
  if (state != RADIOLIB_ERR_NONE) {
    Serial.printf("[lora] tx failed: %d\n", state);
    return false;
  }
  return true;
}

#else  // !ST_HAS_LORA — pure BLE build (demo relay)

LoRaLink* LoRaLink::s_self = nullptr;

bool LoRaLink::begin() {
  up_ = false;
  return false;
}
bool LoRaLink::pollReceive(std::string&) { return false; }
bool LoRaLink::send(const std::string&) { return false; }

#endif