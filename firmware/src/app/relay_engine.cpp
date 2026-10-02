#include "relay_engine.h"

#include <Arduino.h>
#include <sys/time.h>
#include <cctype>
#include <cstdlib>

#include "core/safe_serial.h"

using namespace st;

namespace {
// Honour ST_LED_ACTIVE_LOW so the burst is actually visible on devkits whose
// on-board LED lights on a LOW output.
inline void ledWrite(uint8_t pin, bool on) {
  digitalWrite(pin, (on != ST_LED_ACTIVE_LOW) ? HIGH : LOW);
}
}  // namespace

RelayEngine::RelayEngine() {
  st::Router::Config c;
  c.myId = ST_NODE_ID;
  c.isGateway = (ST_ROLE_GATEWAY != 0);
  c.hasLoRa = false;
  c.maxAgeSec = ST_MSG_MAX_AGE_S;
  c.futureSkewSec = ST_FUTURE_SKEW_S;
  c.seenTtlMs = ST_SEEN_TTL_MS;
  c.clientCtx = this;
  router = st::Router(c);
  router.setClientHook(&RelayEngine::clientAttached, this);
}

bool RelayEngine::clientAttached(const std::string& dst, void* ctx) {
  RelayEngine* e = static_cast<RelayEngine*>(ctx);
  // This node represents a physical tourist (button SOS, no phone attached),
  // so it owns replies addressed to that id even with no BLE client present.
  // The gateway must NOT claim it: rescue replies addressed to the tourist are
  // meant to cross the radio link.
  if (dst == ST_TOURIST_ID && !ST_ROLE_GATEWAY) return true;
  return e->ble.hasClient(dst, millis());
}

bool RelayEngine::begin() {
  Serial.begin(ST_SERIAL_BAUD);
  Serial.printf("[engine] %s node=%s role=%s lora=%d\n", ST_ENGINE_NAME, ST_NODE_ID,
                ST_ROLE_GATEWAY ? "GATEWAY" : "RELAY", ST_HAS_LORA);

  pinMode(ST_LED_GPIO, OUTPUT);
  ledWrite(ST_LED_GPIO, false);
  activeLedPin_ = 0xFF;
#if ST_LED_TX_GPIO >= 0
  pinMode(ST_LED_TX_GPIO, OUTPUT);
  ledWrite(ST_LED_TX_GPIO, false);
  Serial.printf("[engine] dedicated TX LED on GPIO%d\n", ST_LED_TX_GPIO);
#endif
  Serial.printf("[engine] LED rx=flash tx=burst(%dx%dms/%dms) gpio=%d%s\n",
                (int)ST_LED_TX_REPEATS, (int)ST_LED_FLASH_MS, (int)ST_LED_GAP_MS,
                ST_LED_GPIO,
                ST_LED_TX_GPIO >= 0 ? " +tx-pin" : "");

  if (ST_SOS_BUTTON_GPIO >= 0 && !ST_ROLE_GATEWAY) {
    pinMode(ST_SOS_BUTTON_GPIO, INPUT_PULLUP);
    Serial.printf("[engine] SOS on %s by button GPIO%d\n", ST_TOURIST_ID, ST_SOS_BUTTON_GPIO);
  }
  if (ST_BUZZER_GPIO >= 0) {
    pinMode(ST_BUZZER_GPIO, OUTPUT);
    digitalWrite(ST_BUZZER_GPIO, 0);
  }

  if (ST_HAS_LORA) {
    if (!lora.begin()) {
      Serial.println("[engine] LoRa not available; BLE-forward only");
    }
  }
  router.setHasLoRa(ST_HAS_LORA && lora.up());
  router.setLoRaReachable(ST_HAS_LORA && lora.up() && lora.hasActivity());

  if (!ble.begin(ST_NODE_ID)) {
    Serial.println("[engine] FATAL: BLE server init failed");
    return false;
  }
  ble.onInbound = [this](const std::string& json) {
    queueInboundJson(json, 0);
  };
  ble.startAdv();

  mesh.begin();

  bootMs_ = millis();
  lastStatusMs_ = bootMs_;
  lastPruneMs_ = bootMs_;
  return true;
}

void RelayEngine::queueInboundJson(const std::string& json, uint16_t handle) {
  if (json.empty() || json.size() > ST_BLE_CHAR_MAX) return;
  portENTER_CRITICAL(&mux_);
  Inbound in{json, handle};
  inboundBuf_.push_back(in);
  portEXIT_CRITICAL(&mux_);
}

void RelayEngine::run() {
  const uint32_t nowMs = millis();

  // ---- SOS button (relay nodes) ---------------------------------------------
  serviceButton(nowMs);
  driveAlarm(nowMs);

  // ---- LoRa RX -------------------------------------------------------------
  std::string frame;
  int harvested = 0;
  while (lora.pollReceive(frame)) {
    Packet p = parseCompact(frame);
    pulseRx();
    handlePacket(p, "LoRa");
    if (++harvested >= 3) break;
  }
  serviceLeds(nowMs);

  // ---- BLE inbound (queued from peripheral server callbacks) ---------------
  std::vector<Inbound> pending;
  portENTER_CRITICAL(&mux_);
  if (!inboundBuf_.empty()) pending.swap(inboundBuf_);
  portEXIT_CRITICAL(&mux_);
  for (auto& in : pending) {
    Packet p = parseJson(in.json);
    // Any valid packet from a phone proves the phone is here (BLE-attached);
    // register it so RESCUE/ACK/BROAD bound for it DELIVER locally instead of
    // being forwarded to the radio (and eventually dropped). Linking on TRACK
    // only meant an SOS-without-TRACK phone could never receive a rescue reply.
    if (p.valid) ble.linkClient(p.src, in.handle);
    handlePacket(p, "BLE");
  }

  // ---- mesh (central) forwarding --------------------------------------------
  mesh.maintain(nowMs);

  // ---- host serial (gateway) ------------------------------------------------
  if (ST_ROLE_GATEWAY) {
    static std::string line;
    while (Serial.available() > 0) {
      char c = (char)Serial.read();
      if (c == '\n') {
        std::string t = trim(line);
        line.clear();
        if (!t.empty()) handleHostLine(t);
      } else {
        if (line.size() < 600) line += c;
      }
    }
  }

  // ---- periodic maintenance ---------------------------------------------------
  if (nowMs - lastStatusMs_ >= ST_STATUS_PERIOD_MS) {
    lastStatusMs_ = nowMs;
    sendStatus();
  }
  // A phone just connected: after a short grace so it can subscribe to the
  // service at GATT level, push a STATUS so the app shows LoRa-health at once
  // instead of waiting a full period.
  if (ble.consumeConnectPulse()) {
    statusPushAtMs_ = nowMs + ST_STATUS_CONNECT_PUSH_DELAY_MS;
  }
  // Reap client links that dropped, so a stale "attached" entry can't swallow a
  // unicast instead of forwarding it over the radio.
  ble.pruneDroppedClients();
  if (statusPushAtMs_ && (int32_t)(nowMs - statusPushAtMs_) >= 0) {
    statusPushAtMs_ = 0;
    sendStatus();
  }
  if (nowMs - lastPruneMs_ >= 60000) {
    lastPruneMs_ = nowMs;
    router.pruneStore(nowMs, ST_STORE_KEEP_MS);
  }
  if (nowMs - lastAdvMs_ >= 5000) {
    lastAdvMs_ = nowMs;
    ble.ensureAdv();
    ble.refreshClientLiveness();
  }
  router.setHasLoRa(ST_HAS_LORA && lora.up());
  router.setLoRaReachable(ST_HAS_LORA && lora.up() && lora.hasActivity());
}

// ---------------------------------------------------------------------------
// Routing + execution
// ---------------------------------------------------------------------------

void RelayEngine::handlePacket(Packet p, const std::string& device) {
  const long long nowMs = millis();
  // Nodes have no NTP. When an inbound packet carries a wall clock (the
  // gateway's, or a phone's real epoch), adopt it so replies/counters and the
  // router freshness check share a consistent time base across the mesh.
  if (device != "app" && device != "host") tryAdoptTime(p, (uint32_t)nowMs);
  RouteDecision d = router.process(p, device, nowMs, (long long)time(nullptr));
  processDecision(p, d, device);

  if (d.shouldAck) {
    router.onAckSent(d.ackPacket.body, device, nowMs);
    handlePacket(d.ackPacket, "app");
  }
}

void RelayEngine::processDecision(Packet& p, const RouteDecision& d, const std::string& device) {
  for (auto action : d.actions) {
    switch (action) {
      case RouteAction::DELIVER: {
        if (ST_ROLE_GATEWAY) {
          const std::string json = toJson(p);
          safetrails::SafeSerial::instance().println(json.c_str());
          // Persist only real incidents; STATUS heartbeats stay live-only.
          if (onDeliver) onDeliver(json, "gateway", p.type != "STATUS");
          if (p.type == "SOS") startAlarm("SOS received", p);
        } else if (!p.src.empty() && (p.type == "RESCUE" || p.type == "ACK" || p.type == "BROAD")) {
          // A reply/broadcast for the tourist this node speaks for.
          if (p.dst == ST_TOURIST_ID || p.isBroadcast()) {
            Serial.printf("[reply] %s from %s: %s\n", p.type.c_str(), p.src.c_str(),
                          p.body.c_str());
            startAlarm("reply", p);
          }
        }
        // Relay/gateway: also push to any attached phones/clients.
        ble.notifyPacket(p);
        break;
      }
      case RouteAction::LORA_TX: {
        if (ST_HAS_LORA && lora.up()) {
          const std::string frame = toCompact(p, ST_LORA_MAX_PAYLOAD);
          if (lora.send(frame)) {
            router.noteLoRaTx();
            Serial.printf("[lora] tx ok len=%u\n", (unsigned)frame.size());
            // Show the transmit side: the operator must be able to tell at a
            // glance that this node is the one putting the packet on the air.
            pulseTx();
          } else {
            Serial.printf("[lora] tx FAILED len=%u (radio returned an error)\n",
                          (unsigned)frame.size());
          }
        } else {
          Serial.printf("[lora] tx SKIPPED (hasLoRa=%d up=%d)\n",
                        (int)ST_HAS_LORA, (int)lora.up());
        }
        break;
      }
      case RouteAction::BLE_TX:
        // BLE mesh transmit was previously silent on the LED: with LoRa down
        // this is the only path a packet takes, so the node looked dead while
        // it was actually relaying.
        mesh.enqueue(toJson(p));
        pulseTx();
        break;
      case RouteAction::DROP:
        break;
    }
  }
}

// ---------------------------------------------------------------------------
// Host commands (dashboard → gateway over USB serial)
// ---------------------------------------------------------------------------
void RelayEngine::handleHostLine(const std::string& line) {
  // Commands carry a top-level "cmd" key. When absent we accept a plain
  // packet authored by the dashboard (e.g. a RESCUE packet).
  const std::string cmd = [&]() {
    // tiny key lookup on the raw JSON
    size_t i = line.find("\"cmd\"");
    if (i == std::string::npos) return std::string();
    size_t c = line.find(':', i);
    if (c == std::string::npos) return std::string();
    size_t s = line.find_first_of('"', c + 1);
    if (s == std::string::npos) return std::string();
    size_t e = line.find('"', s + 1);
    return (e == std::string::npos) ? std::string() : line.substr(s + 1, e - s - 1);
  }();

  if (cmd == "ack") {
    size_t i = line.find("\"mid\"");
    if (i != std::string::npos) {
      size_t c = line.find(':', i), s = line.find_first_of('"', c + 1),
             e = (s == std::string::npos) ? std::string::npos : line.find('"', s + 1);
      if (e != std::string::npos) {
        std::string mid = line.substr(s + 1, e - s - 1);
        for (auto& row : router.messages()) {
          if (row.packet.mid == mid) {
            Packet ack = makeAck(row.packet, ST_NODE_ID, row.packet.src, 8);
            // This node already auto-acked this SOS with the identical mid, and
            // the duplicate window is 10 minutes, so without forgetting the key
            // the desk's confirmation would be dropped here and the tourist
            // would never learn anyone responded.
            router.forgetSeen(ack.src, ack.type, ack.mid);
            handlePacket(ack, "host");
            break;
          }
        }
      }
    }
    return;
  }

  if (cmd == "rescue") {
    std::string dst, body;
    int prio = 2;
    size_t d = line.find("\"dst\""), b = line.find("\"body\""), p = line.find("\"prio\"");
    if (d != std::string::npos) {
      size_t c = line.find(':', d), s = line.find_first_of('"', c + 1),
             e = (s == std::string::npos) ? std::string::npos : line.find('"', s + 1);
      if (e != std::string::npos) dst = line.substr(s + 1, e - s - 1);
    }
    if (b != std::string::npos) {
      size_t c = line.find(':', b), s = line.find_first_of('"', c + 1),
             e = (s == std::string::npos) ? std::string::npos : line.find('"', s + 1);
      if (e != std::string::npos) body = line.substr(s + 1, e - s - 1);
    }
    if (p != std::string::npos) {
      size_t c = line.find(':', p);
      std::string v;
      for (size_t k = c + 1; k < line.size() && (line[k] == ' ' || isdigit((unsigned char)line[k])); k++) {
        if (isdigit((unsigned char)line[k])) v += line[k];
      }
      if (!v.empty()) prio = atoi(v.c_str());
    }
    if (!dst.empty()) handlePacket(makeRescue(ST_NODE_ID, dst, prio, body, 8), "host");
    return;
  }

  if (cmd == "broad") {
    std::string body;
    int prio = 3;
    size_t b = line.find("\"body\""), p = line.find("\"prio\"");
    if (b != std::string::npos) {
      size_t c = line.find(':', b), s = line.find_first_of('"', c + 1),
             e = (s == std::string::npos) ? std::string::npos : line.find('"', s + 1);
      if (e != std::string::npos) body = line.substr(s + 1, e - s - 1);
    }
    if (p != std::string::npos) {
      size_t c = line.find(':', p);
      std::string v;
      for (size_t k = c + 1; k < line.size() && (line[k] == ' ' || isdigit((unsigned char)line[k])); k++) {
        if (isdigit((unsigned char)line[k])) v += line[k];
      }
      if (!v.empty()) prio = atoi(v.c_str());
    }
    handlePacket(makeBroadcast(ST_NODE_ID, "EMERGENCY", body, "-", prio, (long long)time(nullptr)), "host");
    return;
  }

  if (cmd == "status_req") {
    sendStatus();
    return;
  }

  // Otherwise: a raw packet JSON (from dashboard "send message" flow).
  Packet p = parseJson(line);
  if (p.valid) handlePacket(p, "host");
}

// ---------------------------------------------------------------------------
// STATUS heartbeat
// ---------------------------------------------------------------------------
std::string RelayEngine::statusBody() {
  char buf[320];
  auto c = router.counters();
  const bool reach = ST_HAS_LORA && lora.up() && lora.hasActivity();
  const char* rst = "unknown";
#if defined(ESP32)
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: rst = "poweron"; break;
    case ESP_RST_EXT: rst = "ext"; break;
    case ESP_RST_SW: rst = "sw"; break;
    case ESP_RST_PANIC: rst = "panic"; break;
    case ESP_RST_INT_WDT: rst = "int_wdt"; break;
    case ESP_RST_TASK_WDT: rst = "task_wdt"; break;
    case ESP_RST_WDT: rst = "wdt"; break;
    case ESP_RST_DEEPSLEEP: rst = "deepsleep"; break;
    case ESP_RST_BROWNOUT: rst = "brownout"; break;
    case ESP_RST_SDIO: rst = "sdio"; break;
    default: break;
  }
#endif
  snprintf(buf, sizeof(buf),
           "node=%s role=%s lora=%d reach=%d adv=%d rssi=%.1f snr=%.1f rx=%u loraTx=%u drop=%u "
           "seen=%u fwd=%u peers=%s clients=%s rst=%s uptime=%lus mem=%u",
           ST_NODE_ID, ST_ROLE_GATEWAY ? "gateway" : "relay", (int)(ST_HAS_LORA && lora.up()),
           (int)reach, (int)ble.isAdvertising(),
           (double)lora.lastRssi(), (double)lora.lastSnr(), c.rx, c.loraTx, c.dropped,
           c.seenDupes, c.forwarded, mesh.peerSummary().c_str(), ble.peerSummary().c_str(),
           rst, (unsigned long)((millis() - bootMs_) / 1000), (unsigned)ESP.getFreeHeap());
  return buf;
}

void RelayEngine::sendStatus() {
  Packet s;
  s.type = "STATUS";
  s.prio = 1;
  s.mid = "ST" + std::to_string((unsigned long)millis());
  s.src = ST_NODE_ID;
  s.dst = "RCUE";
  s.ts = (long long)time(nullptr);
  s.hop = 0;
  s.ttl = 1;
  s.flags = 0;
  s.body = statusBody();
  handlePacket(s, "app");
  // Push our link health to any attached phone so the app can show
  // LoRa vs BLE vs Online connectivity. Harmless no-op with no clients.
  ble.notifyPacket(s);
  // LoRa heartbeat so remote peers keep a live link signal (also the mesh's
  // de-facto time beacon: peers sync their clock off src==RCUE status packets).
  // No LED pulse here: the 30 s heartbeat runs on every node, so blinking for
  // it would make the pin useless as a "this SOS just went out" signal.
  if (ST_HAS_LORA && lora.up()) {
    lora.send(toCompact(s, ST_LORA_MAX_PAYLOAD));
  }
}

// ---------------------------------------------------------------------------
// LED indications.
//
// One scheduler owns every blink so indications can never fight: a transmit
// burst is never truncated by an arriving packet and vice versa, and the alarm
// blinks defer to real traffic.
//
//   RX : one short flash          (something arrived on the radio)
//   TX : repeating burst          (this node is sending -- SOS, rescue,
//                                  broadcast or an ack, over LoRa or BLE)
//
// A node that has LoRa up and reachable adds BOTH RouteAction::LORA_TX and
// BLE_TX for every forwarded packet, so both transmit paths pulse; the burst
// restart guard collapses that into a single visible burst.
// ---------------------------------------------------------------------------
void RelayEngine::setLedPin(uint8_t pin, bool on) {
  if (activeLedPin_ != 0xFF && activeLedPin_ != pin) {
    ledWrite(activeLedPin_, false);
    activeLedPin_ = 0xFF;
  }
  ledWrite(pin, on);
  if (on) activeLedPin_ = pin;
}

void RelayEngine::pulseRx() {
  // Never stomp a transmit burst: "I am sending" is the more important fact.
  if (txBurstActive_) return;
  if (ledRepeatsLeft_ > 1) return;
  ledRepeatsLeft_ = 1;
  ledPhaseEndMs_ = 0;   // start on the next serviceLeds() call
}

void RelayEngine::pulseTx() {
  const uint32_t now = millis();
  // LoRa + BLE both fire for one packet microseconds apart; ignore the second
  // so the console shows one burst instead of two.
  if (txBurstActive_ && now - txBurstStartMs_ < 200) return;
  ledRepeatsLeft_ = ST_LED_TX_REPEATS;
  ledPhaseEndMs_ = 0;
  txBurstActive_ = true;
  txBurstStartMs_ = now;
  Serial.printf("[led] tx burst x%d on gpio=%d\n", (int)ST_LED_TX_REPEATS,
                ST_LED_TX_GPIO >= 0 ? ST_LED_TX_GPIO : ST_LED_GPIO);
}

void RelayEngine::serviceLeds(uint32_t nowMs) {
  if (ledRepeatsLeft_ == 0) {
    if (ledOn_) {
      const uint8_t pin = activeLedPin_;
      activeLedPin_ = 0xFF;
      ledWrite(pin, false);
      ledOn_ = false;
    }
    return;
  }
  if (nowMs < ledPhaseEndMs_) return;

  const uint8_t pin = (txBurstActive_ && ST_LED_TX_GPIO >= 0)
                          ? (uint8_t)ST_LED_TX_GPIO
                          : (uint8_t)ST_LED_GPIO;
  if (ledOn_) {
    setLedPin(pin, false);
    ledOn_ = false;
    if (--ledRepeatsLeft_ == 0) {
      txBurstActive_ = false;
      return;
    }
    ledPhaseEndMs_ = nowMs + ST_LED_GAP_MS;
  } else {
    setLedPin(pin, true);
    ledOn_ = true;
    ledPhaseEndMs_ = nowMs + ST_LED_FLASH_MS;
  }
}

// ---------------------------------------------------------------------------
// SOS button flow (relay nodes), LED/buzzer alarm, mesh time-sync
// ---------------------------------------------------------------------------

void RelayEngine::triggerSos() {
  Packet s = makeSos(ST_TOURIST_ID, ST_SOS_DEMO_LAT, ST_SOS_DEMO_LON,
                     ST_SOS_BODY, ST_INITIAL_TTL);
  Serial.printf("[sos] button: mid=%s src=%s dst=RCUE → LoRa+BLE\n",
                s.mid.c_str(), s.src.c_str());
  handlePacket(s, "app");  // router floods LoRa (primary) + BLE (fallback)
  startAlarm("SOS sent", s);
}

void RelayEngine::serviceButton(uint32_t nowMs) {
  if (ST_ROLE_GATEWAY || ST_SOS_BUTTON_GPIO < 0) return;
  const bool pressed = digitalRead(ST_SOS_BUTTON_GPIO) == LOW;  // active-low
  if (pressed && !btnPrevPressed_ && nowMs - btnLastMs_ >= ST_SOS_DEBOUNCE_MS) {
    btnLastMs_ = nowMs;
    triggerSos();
  }
  btnPrevPressed_ = pressed;
}

void RelayEngine::startAlarm(const char* why, const st::Packet& p) {
  alarmEndMs_ = millis() + ST_ALARM_MS;
  (void)why;
  (void)p;
}

void RelayEngine::driveAlarm(uint32_t nowMs) {
  if (!alarmEndMs_) return;
  if (nowMs > alarmEndMs_) {
    alarmEndMs_ = 0;
    // Do not cut a transmit burst short at the buzzer's expense.
    if (ledRepeatsLeft_ == 0 && !ledOn_) {
      activeLedPin_ = 0xFF;
      ledWrite(ST_LED_GPIO, false);
#if ST_LED_TX_GPIO >= 0
      ledWrite(ST_LED_TX_GPIO, false);
#endif
    }
    if (ST_BUZZER_GPIO >= 0) digitalWrite(ST_BUZZER_GPIO, LOW);
    return;
  }
  // Real traffic outranks the decorative alarm blink.
  if (ledRepeatsLeft_ > 0 || ledOn_) return;
  const bool on = (nowMs % 300) < 150;  // ~3 pulses over the alarm window
  ledWrite(ST_LED_GPIO, on);
  activeLedPin_ = on ? (uint8_t)ST_LED_GPIO : 0xFF;
  if (ST_BUZZER_GPIO >= 0) digitalWrite(ST_BUZZER_GPIO, on ? HIGH : LOW);
}

bool RelayEngine::tryAdoptTime(const st::Packet& p, uint32_t nowMs) {
  if (p.ts <= 0) return false;
  if (nowMs - lastSyncMs_ < ST_TIME_SYNC_MIN_GAP_MS) return false;

  // Trusted sources: a real wall-clock epoch (phone app with NTP) from anyone,
  // or the boot-relative clock of the rescue gateway (src RCUE).
  const bool realEpoch = p.ts > 1600000000LL;
  const bool fromGateway = p.src == "RCUE";
  if (!realEpoch && !fromGateway) return false;

  const long long wall = (long long)time(nullptr);
  if (wall > 1600000000LL && p.ts < 1600000000LL) return false;  // never regress
  const long long dx = (p.ts > wall) ? (p.ts - wall) : (wall - p.ts);
  if (dx <= 3) return false;

  timeval tv;
  tv.tv_sec = (time_t)p.ts;
  tv.tv_usec = 0;
  settimeofday(&tv, nullptr);
  lastSyncMs_ = nowMs;
  safetrails::SafeSerial::instance().printf("[time] synced %lld -> %lld from %s (type=%s)\n", wall, p.ts,
                p.src.c_str(), p.type.c_str());
  return true;
}