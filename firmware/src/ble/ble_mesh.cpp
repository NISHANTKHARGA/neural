#include "ble_mesh.h"
#include "ble_server.h"

#include "../core/packet.h"
#include "ble_server.h"

namespace {
constexpr uint32_t kFlushCooldownMs = 600;
constexpr uint32_t kDrainPerMaintain = 3;
}  // namespace

void BleMesh::begin() {
  Serial.println("[mesh] central client ready");
}

void BleMesh::enqueue(std::string json) {
  std::lock_guard<std::mutex> lk(mutex_);
  if (queue_.size() > 32) return;  // bound memory
  queue_.push_back(std::move(json));
}

std::string BleMesh::peerSummary() {
  std::lock_guard<std::mutex> lk(mutex_);
  std::string s;
  for (auto& kv : peers_) {
    if (!s.empty()) s += ", ";
    s += kv.first;
  }
  return s.empty() ? "none" : s;
}

void BleMesh::scanNow() {
  if (NimBLEDevice::getScan()->isScanning()) return;

  // Short active scan; peripheral advertising continues concurrently.
  NimBLEDevice::getScan()->start(3000, false);
  NimBLEScanResults results = NimBLEDevice::getScan()->getResults();
  uint32_t now = millis();
  std::map<std::string, Peer> fresh;
  const NimBLEUUID svc(ST_SVC_UUID);

  // Carry connection-failure backoff across rescans. Without this every scan
  // rebuilt the peer table with a clean slate and an uncooperative peer was
  // retried immediately, forever.
  std::map<std::string, std::pair<uint8_t, uint32_t>> prev;
  {
    std::lock_guard<std::mutex> lk(mutex_);
    for (auto& kv : peers_) {
      prev[kv.first] = {kv.second.fails, kv.second.failUntilMs};
    }
  }

  for (int i = 0; i < results.getCount() && i < 12; i++) {
    const NimBLEAdvertisedDevice* d = results.getDevice(i);
    std::string name = (d ? d->getName() : "");
    bool isRelay = (d && d->isAdvertisingService(svc));
    if (name.rfind(ST_BLE_ADV_NAME, 0) == 0) isRelay = true;
    if (!isRelay) continue;

    Peer p;
    p.addr = (d ? d->getAddress() : NimBLEAddress());
    p.rssi = (d ? (int8_t)d->getRSSI() : -127);
    p.lastSeenMs = now;
    const std::string key = p.addr.toString();
    auto it = prev.find(key);
    if (it != prev.end()) {
      p.fails = it->second.first;
      p.failUntilMs = it->second.second;
    }
    fresh[key] = p;
    Serial.printf("[mesh] neighbor: %s rssi=%d\n", p.addr.toString(), p.rssi);
  }

  {
    std::lock_guard<std::mutex> lk(mutex_);
    peers_ = std::move(fresh);
  }
}

NimBLEAddress BleMesh::pickPeer() const {
  NimBLEAddress best;
  int8_t bestRssi = -127;
  uint32_t now = millis();
  for (auto& kv : peers_) {
    if (now - kv.second.lastSeenMs > ST_MESH_PEER_TTL_MS) continue;
    if (now < kv.second.failUntilMs) continue;  // backing off after a failure
    if (kv.second.rssi > bestRssi) {
      bestRssi = kv.second.rssi;
      best = kv.second.addr;
    }
  }
  return best;
}

bool BleMesh::flushOne() {
  std::string json;
  {
    std::lock_guard<std::mutex> lk(mutex_);
    if (queue_.empty()) return false;
  }
  if (clientBusy_) return false;
  if (millis() - lastFlushMs_ < kFlushCooldownMs) return false;

  NimBLEAddress target = pickPeer();
  if (target.isNull()) {
    // No known peer yet: let maintain() scan first, retry shortly.
    return false;
  }

  clientBusy_ = true;
  bool ok = false;

  if (!client_) client_ = NimBLEDevice::createClient();

  {
    std::lock_guard<std::mutex> lk(mutex_);
    if (!queue_.empty()) {
      json = queue_.front();
    }
  }
  if (json.empty()) {
    clientBusy_ = false;
    return false;
  }

  Serial.printf("[mesh] forwarding to %s (%d queued)\n", target.toString().c_str(),
                (int)queue_.size());

  if (client_->connect(target, false)) {
    NimBLERemoteService* svc = client_->getService(ST_SVC_UUID);
    if (svc) {
      NimBLERemoteCharacteristic* ch = svc->getCharacteristic(ST_SOS_TX);
      if (ch && ch->writeValue((uint8_t*)json.data(), json.size(), true)) {
        ok = true;
      }
    }
    client_->disconnect();
  }

  const std::string key = target.toString();
  uint8_t failNo = 0;
  {
    std::lock_guard<std::mutex> lk(mutex_);
    auto it = peers_.find(key);
    if (it != peers_.end()) {
      if (ok) {
        it->second.fails = 0;
        it->second.failUntilMs = 0;
      } else {
        // Exponential backoff, capped: 5s, 10s, 20s, 40s, 60s...
        it->second.fails++;
        failNo = it->second.fails;
        uint32_t wait = 5000u << (failNo > 4 ? 4 : failNo - 1);
        if (wait > 60000u) wait = 60000u;
        it->second.failUntilMs = millis() + wait;
      }
    }
  }
  if (!ok) {
    // Our own line, so the console explains itself instead of leaving a bare
    // NimBLE "Connection failed" with no hint of what happened next.
    Serial.printf("[mesh] peer %s refused (fail #%u), backing off\n",
                  key.c_str(), (unsigned)failNo);
  }

  if (ok) {
    std::lock_guard<std::mutex> lk(mutex_);
    if (!queue_.empty()) queue_.pop_front();
    lastFlushMs_ = millis();
  }
  clientBusy_ = false;
  return ok;
}

void BleMesh::maintain(long long nowMs) {
  (void)nowMs;
  uint32_t now = millis();
  if (now - lastScanMs_ >= ST_MESH_SCAN_PERIOD_MS) {
    lastScanMs_ = now;
    scanNow();
  }
  for (int i = 0; i < kDrainPerMaintain; i++) {
    if (!flushOne()) break;
  }
}