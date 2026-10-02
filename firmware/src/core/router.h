#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "packet.h"

namespace st {

// ---------------------------------------------------------------------------
// Seen-cache: fixed-size ring buffer for duplicate detection / replay guard.
// ---------------------------------------------------------------------------
class SeenCache {
 public:
  explicit SeenCache(size_t capacity = 128) : cap_(capacity) {}

  void clear() {
    keys_.clear();
    expiresMs_.clear();
  }

  // Returns true if `key` is already present and not expired; otherwise records it.
  bool seen(const std::string& key, long long nowMs, long long ttlMs) {
    for (size_t i = 0; i < keys_.size(); ++i) {
      if (keys_[i] == key) {
        if (nowMs <= expiresMs_[i]) return true;
        keys_[i] = key;
        expiresMs_[i] = nowMs + ttlMs;
        return false;
      }
    }
    if (keys_.size() >= cap_) {
      keys_.erase(keys_.begin());
      expiresMs_.erase(expiresMs_.begin());
    }
    keys_.push_back(key);
    expiresMs_.push_back(nowMs + ttlMs);
    return false;
  }

  // Drop a single key so a deliberate re-emission of an identity this node has
  // already sent is not swallowed as a duplicate. Needed because a desk ACK
  // reuses the automatic ACK's mid ("ACK-<mid>"), and the cache would otherwise
  // discard the operator's confirmation for the whole TTL window.
  void forget(const std::string& key) {
    for (size_t i = 0; i < keys_.size(); ++i) {
      if (keys_[i] == key) {
        keys_.erase(keys_.begin() + i);
        expiresMs_.erase(expiresMs_.begin() + i);
        return;
      }
    }
  }

 private:
  size_t cap_;
  std::vector<std::string> keys_;
  std::vector<long long> expiresMs_;
};

// ---------------------------------------------------------------------------
// Message store: per-message row with lifecycle state + last device.
// ---------------------------------------------------------------------------
struct MessageRow {
  Packet packet;
  std::string status;
  std::string lastDevice;
  long long lastSeenMs = 0;
  long long rxAtMs = 0;
};

class MessageStore {
 public:
  // Hard safety cap: beyond this the oldest row is dropped so a memory bug can
  // never OOM-abort the node (bad_alloc -> terminate). Emergency traffic is
  // rare and short, so 400 rows is far beyond realistic incident volume.
  static constexpr size_t kHardCap = 400;

  void upsert(const Packet& p, const std::string& status, const std::string& device, long long nowMs);
  void markAcked(const std::string& mid, const std::string& device, long long nowMs);
  const std::vector<MessageRow>& rows() const { return rows_; }
  size_t size() const { return rows_.size(); }
  void prune(long long nowMs, long long keepMs);

 private:
  std::vector<MessageRow> rows_;
};

// ---------------------------------------------------------------------------
// Router decisions: a single inbound packet can produce several actions
// (e.g. a broadcast is delivered locally AND flooded on LoRa + BLE).
// ---------------------------------------------------------------------------
enum class RouteAction { DELIVER, LORA_TX, BLE_TX, DROP };

struct RouteDecision {
  std::string reason;
  std::vector<RouteAction> actions;
  bool shouldAck = false;   // caller should transmit ackPacket
  Packet ackPacket;
};

// ---------------------------------------------------------------------------
// Router: validate → de-duplicate → freshness → store → decide actions.
// The caller executes the actual LoRa / BLE transmits. Pure C++ (host-testable).
// ---------------------------------------------------------------------------
class Router {
 public:
  // Client-lookup lets the router treat "the rescue dst / tourist dst is
  // connected to THIS node" as a local delivery (not a forward).
  struct Config {
    std::string myId = "N-A";
    bool isGateway = false;
    bool hasLoRa = false;
    // LoRa-preference hint set by the engine each run: true when a LoRa peer
    // was heard recently (ST_LORA_REACHABLE_WINDOW_MS). Reachable -> transmit on
    // LoRa only (no BLE flood). Unreachable -> flood LoRa + BLE so a multi-hop
    // BLE mesh can still carry the packet ("LoRa if in range, else BLE hop").
    bool loRaReachable = false;
    int maxAgeSec = 300;
    int futureSkewSec = 60;
    int seenTtlMs = 600000;  // 10-minute duplicate window
    bool (*hasClient)(const std::string& touristId, void* ctx) = nullptr;
    void* clientCtx = nullptr;
  };

  Router() = default;
  explicit Router(const Config& cfg) : cfg_(cfg) {}

  // Validates, de-duplicates, checks freshness against `nowWallSec` (wall-clock
  // seconds; node clocks are mesh-synced upstream), and decides actions.
  // `nowMs` (millis) is used for the seen-cache TTL only, so a node that syncs
  // / boots late never misuses the two time bases.
  RouteDecision process(Packet& p, const std::string& device, long long nowMs,
                        long long nowWallSec);

  bool ackFor(const Packet& p, Packet& out) const;
  void onAckSent(const std::string& mid, const std::string& device, long long nowMs);

  // Let the app layer re-emit an identity this node has already sent/seen. A
  // desk ACK deliberately reuses the automatic ACK's mid, so without this the
  // duplicate filter drops it and the operator's confirmation never reaches the
  // tourist's phone.
  void forgetSeen(const std::string& src, const std::string& type, const std::string& mid) {
    seen_.forget(src + ":" + type + ":" + mid);
  }

  void setClientHook(bool (*cb)(const std::string&, void*), void* ctx) {
    cfg_.hasClient = cb;
    cfg_.clientCtx = ctx;
  }

  const std::vector<MessageRow>& messages() const { return store_.rows(); }
  const Config& config() const { return cfg_; }
  void setHasLoRa(bool v) { cfg_.hasLoRa = v; }
  void setLoRaReachable(bool v) { cfg_.loRaReachable = v; }
  void pruneStore(long long nowMs, long long keepMs) { store_.prune(nowMs, keepMs); }

  struct Counters {
    uint32_t rx = 0, loraTx = 0, dropped = 0, seenDupes = 0, forwarded = 0;
  };
  Counters counters() const { return counters_; }

  // LoRa transmits are counted here, not inferred: `loraTx` used to be declared
  // but never incremented, so the STATUS heartbeat reported 0 forever and a
  // dead radio was indistinguishable from an idle one.
  void noteLoRaTx() { ++counters_.loraTx; }
  void noteRx() { ++counters_.rx; }

 private:
  Config cfg_;
  SeenCache seen_;
  MessageStore store_;
  Counters counters_;
};

}  // namespace st