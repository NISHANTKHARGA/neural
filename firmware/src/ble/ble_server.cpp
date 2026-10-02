#include "ble_server.h"

#include <functional>

#include "../config.h"

namespace {
NimBLEServer* g_server = nullptr;
BleServer* g_ble = nullptr;  // set by begin(), used only by static callbacks

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo& info) override {
    (void)info;
    Serial.println("[ble] client connected");
    if (g_ble) g_ble->noteConnect();
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo& info, int reason) override {
    Serial.printf("[ble] client disconnected (reason %d)\n", reason);
    if (g_ble) g_ble->noteDisconnect(info.getConnHandle());
  }
};

class WriteCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chrc, NimBLEConnInfo& info) override {
    (void)chrc;
    (void)info;
    std::string val = chrc->getValue();
    if (val.empty()) return;
    if (g_ble && g_ble->onInbound) g_ble->onInbound(val);
  }
};
}  // namespace

bool BleServer::begin(const char* nodeId) {
  NimBLEDevice::init(nodeId);
  // Ask for the largest ATT payload up front. Android negotiates downwards from
  // what we offer, so leaving NimBLE's 23-byte default in place caps every
  // notification at 20 bytes -- and our packets are 190-330 bytes, so each one
  // would be rejected and the phone would receive nothing at all.
  NimBLEDevice::setMTU(517);
  NimBLEDevice::setPower(ESP_PWR_LVL_P6);  // 0 dBm boosted default

  server_ = NimBLEDevice::createServer();
  server_->setCallbacks(new ServerCallbacks());
  server_->advertiseOnDisconnect(true);  // resume advertising after a drop

  NimBLEService* svc = server_->createService(ST_SVC_UUID);
  if (!svc) return false;

  auto add = [&](const char* uuid, uint32_t props) -> NimBLECharacteristic* {
    NimBLECharacteristic* c = svc->createCharacteristic(uuid, props);
    return c;
  };

  // Phone / peer-relay inbound write endpoints.
  NimBLECharacteristic* sosTx = add(ST_SOS_TX, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  NimBLECharacteristic* aclTx = add(ST_ACL_TX, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  (void)sosTx; (void)aclTx;

  // Phone outbound notify endpoints.
  sosRx_ = add(ST_SOS_RX, NIMBLE_PROPERTY::NOTIFY);
  rescueRx_ = add(ST_RES_RX, NIMBLE_PROPERTY::NOTIFY);
  broadRx_ = add(ST_BRDC_RX, NIMBLE_PROPERTY::NOTIFY);
  statRx_ = add(ST_STAT_RX, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  dataRx_ = add(ST_DATA_RX, NIMBLE_PROPERTY::NOTIFY);

  if (!sosRx_ || !rescueRx_ || !broadRx_ || !statRx_ || !dataRx_) return false;

  WriteCallbacks* wcb = new WriteCallbacks();
  for (auto it = svc->getCharacteristics().begin(); it != svc->getCharacteristics().end(); ++it) {
    NimBLECharacteristic* c = *it;
    uint32_t props = c->getProperties();
    if (props & NIMBLE_PROPERTY::WRITE) c->setCallbacks(wcb);
  }
  svc->start();

  g_server = server_;
  g_ble = this;

  if (onInbound == nullptr) {
    onInbound = [](const std::string&) {};
  }
  Serial.println("[ble] server up (SAFETRAILS_RELAY)");
  return true;
}

void BleServer::startAdv() {
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->setName(ST_BLE_ADV_NAME);
  // Deliberately NOT advertising ST_SVC_UUID. The legacy payload is 31 bytes and
  // a 128-bit UUID costs 16 of them, so NimBLE silently drops it ("Cannot add
  // UUID, data length exceeded") and the node stays invisible to any scanner
  // that filters on the service UUID. Phones match on the name prefix instead,
  // which is what identifies a node to a rescuer anyway.
  adv->setMinInterval(0x20);  // 20 ms (0.625 ms units) - BLE min is 0x20
  adv->setMaxInterval(0x30);  // 30 ms
  if (!NimBLEDevice::startAdvertising()) {
    Serial.println("[ble] startAdvertising FAILED");
    return;
  }
  Serial.printf("[ble] advertising as %s\n", ST_BLE_ADV_NAME);
}

void BleServer::ensureAdv() {
  // Watchdog: keep the relay discoverable. NimBLE stops advertising once a
  // client connects; if that connection drops (phone closed app / BT off),
  // advertiseOnDisconnect restarts it. This is the belt-and-braces fallback
  // in case the disconnect event is missed.
  if (!server_ || server_->getConnectedCount() > 0) return;
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  if (!adv || adv->isAdvertising()) return;
  if (!NimBLEDevice::startAdvertising()) {
    Serial.println("[ble] re-advertising FAILED");
    return;
  }
  Serial.println("[ble] re-advertising (watchdog) OK");
}

void BleServer::notifyPacket(const st::Packet& p) {
  const std::string json = st::toJson(p);
  NimBLECharacteristic* ch = nullptr;
  if (p.type == "SOS" || p.type == "ACK") ch = sosRx_;
  else if (p.type == "RESCUE") ch = rescueRx_;
  else if (p.type == "BROAD") ch = broadRx_;
  else if (p.type == "STATUS") ch = statRx_;
  else ch = dataRx_;
  if (!ch) return;
  ch->setValue((uint8_t*)json.data(), json.size());
  // NimBLE's notify() only returns a bool, and every failure mode (MTU too
  // small, no subscriber, TX buffers full) looks identical from the outside. A
  // packet larger than MTU-3 is rejected outright, so report the negotiated MTU
  // next to the failure: without it "the phone showed nothing" is undiagnosable.
  const bool sent = ch->notify();
  uint16_t mtu = 0;
  const uint8_t peers = server_ ? server_->getConnectedCount() : 0;
  if (server_) {
    if (peers > 0) mtu = server_->getPeerInfo(0).getMTU();
  }
  const uint16_t payloadMax = mtu > 3 ? (uint16_t)(mtu - 3) : 0;
  if (sent && peers == 0) {
    // NimBLE reports notify() == true even with nobody subscribed, so this
    // used to log "notify ok" while the packet went nowhere -- which is exactly
    // why "the dashboard says it sent RESCUE but the app shows nothing" was
    // undiagnosable. Say plainly that there was no phone to send it to.
    Serial.printf("[ble] notify DROPPED %s len=%u (no phone connected)\n",
                  p.type.c_str(), (unsigned)json.size());
  } else if (sent) {
    Serial.printf("[ble] notify ok %s len=%u mtu=%u\n", p.type.c_str(),
                  (unsigned)json.size(), (unsigned)mtu);
  } else {
    Serial.printf("[ble] notify FAILED %s len=%u mtu=%u payloadMax=%u peers=%u\n",
                  p.type.c_str(), (unsigned)json.size(), (unsigned)mtu,
                  (unsigned)payloadMax, (unsigned)peers);
  }
}

void BleServer::linkClient(const std::string& touristId, uint16_t handle) {
  clients_[handle].touristId = touristId;
  clients_[handle].lastSeenMs = millis();
}

bool BleServer::hasClient(const std::string& dst, long long nowMs) {
  (void)nowMs;
  const uint32_t now = millis();
  const uint32_t ttlLink = ST_MESH_PEER_TTL_MS;
  for (auto kv : clients_) {
    if (kv.second.touristId == dst) {
      if ((now - kv.second.lastSeenMs) >= ttlLink) return false;
      // Silent drop (out of range, phone sleep): the disconnect callback is not
      // guaranteed to fire, so confirm the handle is still in the link layer
      // before we let the router call this a local delivery.
      if (server_) {
        const uint8_t live = server_->getConnectedCount();
        bool stillThere = false;
        for (uint8_t i = 0; i < live; ++i) {
          if (server_->getPeerInfo(i).getConnHandle() == kv.first) {
            stillThere = true;
            break;
          }
        }
        if (!stillThere) return false;
      }
      return true;
    }
  }
  return false;
}

void BleServer::pruneDroppedClients() {
  // A handle reported by the disconnect callback is gone from the link layer.
  for (auto it = clients_.begin(); it != clients_.end();) {
    bool gone = false;
    for (size_t i = 0; i < kDroppedRing; ++i) {
      if (dropped_[i] == it->first) {
        gone = true;
        break;
      }
    }
    if (gone) {
      Serial.printf("[ble] unlinked %s (disconnected)\n", it->second.touristId.c_str());
      it = clients_.erase(it);
    } else {
      ++it;
    }
  }
  // Keep the ring cheap: clear it once it has been drained.
  droppedAt_ = 0;
  for (size_t i = 0; i < kDroppedRing; ++i) dropped_[i] = 0xFFFF;
}

void BleServer::refreshClientLiveness() {
  if (!server_) return;
  const uint8_t live = server_->getConnectedCount();
  if (live == 0) return;
  const uint32_t now = millis();
  for (auto& kv : clients_) {
    for (uint8_t i = 0; i < live; ++i) {
      if (server_->getPeerInfo(i).getConnHandle() == kv.first) {
        kv.second.lastSeenMs = now;
        break;
      }
    }
  }
}

std::string BleServer::peerSummary() {
  std::string s;
  for (auto& kv : clients_) {
    if (!s.empty()) s += ", ";
    s += kv.second.touristId;
  }
  return s.empty() ? "none" : s;
}