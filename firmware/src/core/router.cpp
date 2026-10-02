#include "router.h"

namespace st {

void MessageStore::upsert(const Packet& p, const std::string& status,
                          const std::string& device, long long nowMs) {
  for (auto& r : rows_) {
    if (r.packet.mid == p.mid && r.packet.src == p.src && r.packet.type == p.type) {
      r.packet = p;
      r.status = status;
      if (!device.empty()) r.lastDevice = device;
      r.lastSeenMs = nowMs;
      return;
    }
  }
  MessageRow r;
  r.packet = p;
  r.status = status;
  r.lastDevice = device;
  r.lastSeenMs = nowMs;
  r.rxAtMs = nowMs;
  if (rows_.size() >= MessageStore::kHardCap) {
    rows_.erase(rows_.begin());
  }
  rows_.push_back(r);
}

void MessageStore::markAcked(const std::string& mid, const std::string& device, long long nowMs) {
  for (auto& r : rows_) {
    if (r.packet.mid == mid) {
      r.status = "ACKNOWLEDGED";
      r.lastSeenMs = nowMs;
      if (!device.empty()) r.lastDevice = device;
      break;
    }
  }
}

void MessageStore::prune(long long nowMs, long long keepMs) {
  std::vector<MessageRow> keep;
  keep.reserve(rows_.size());
  for (auto& r : rows_) {
    if (nowMs - r.lastSeenMs <= keepMs) keep.push_back(r);
  }
  rows_ = std::move(keep);
}

// ---------------------------------------------------------------------------

static const char* STATUS_REASONS[] = {"INVALID", "UNKNOWN_TYPE", "MISSING_ID",
                                       "BAD_CHECKSUM", "BAD_VERSION"};

RouteDecision Router::process(Packet& p, const std::string& device, long long nowMs,
                              long long nowWallSec) {
  RouteDecision d;

  if (!p.valid) {
    ++counters_.dropped;
    d.actions.push_back(RouteAction::DROP);
    d.reason = p.invalidReason.empty() ? "INVALID" : p.invalidReason;
    return d;
  }

  // ---- freshness ---------------------------------------------------------
  // Node-internal heartbeat types (STATUS/PING/PONG) carry whatever the local
  // clock says (often pre-NTP residue) and are destined for the app layer only,
  // so they are exempt from the age/future policy. TRACK is plain GPS telemetry
  // which is not critical-repeatable, so age is ignored for it too.
  if (p.ts != 0 && (p.type != "TRACK")) {
    if (p.type != "STATUS" && p.type != "PING" && p.type != "PONG") {
      long long ageSec = nowWallSec - p.ts;
      if (ageSec > cfg_.maxAgeSec) {
        ++counters_.dropped;
        d.actions.push_back(RouteAction::DROP);
        d.reason = "STALE";
        return d;
      }
      if (p.ts > nowWallSec + cfg_.futureSkewSec) {
        ++counters_.dropped;
        d.actions.push_back(RouteAction::DROP);
        d.reason = "FUTURE";
        return d;
      }
    }
  }

  ++counters_.rx;

  // ---- duplicate suppression ----------------------------------------------
  const std::string seenKey = p.src + ":" + p.type + ":" + p.mid;
  if (seen_.seen(seenKey, nowMs, cfg_.seenTtlMs)) {
    ++counters_.seenDupes;
    ++counters_.dropped;
    d.actions.push_back(RouteAction::DROP);
    d.reason = "SEEN";
    return d;
  }

  // Node-internal types are delivered to the upper layer, never flooded, and
  // never stored: every heartbeat has a unique mid, so storing them would grow
  // the message store forever until the heap is exhausted (OOM abort). The
  // dashboard receives these live over the socket; it does not need history.
  if (p.type == "STATUS" || p.type == "PING" || p.type == "PONG") {
    d.actions.push_back(RouteAction::DELIVER);
    d.reason = "internal";
    return d;
  }

  const bool clientHere =
      cfg_.hasClient != nullptr && cfg_.hasClient(p.dst, cfg_.clientCtx);
  const bool destMe = p.isBroadcast() || p.dst == cfg_.myId ||
                      (cfg_.isGateway && (p.dst == "RCUE" || p.dst == "*")) ||
                      clientHere;

  const bool forwardNeeded = p.isBroadcast() || !destMe;

  // ---- local presentation --------------------------------------------------
  if (destMe) {
    d.actions.push_back(RouteAction::DELIVER);
    store_.upsert(p, "RECEIVED", device, nowMs);
  }

  // ---- acknowledgement ------------------------------------------------------
  if (destMe && p.ackRequired() && p.type != "ACK") {
    Packet ack;
    if (ackFor(p, ack)) {
      d.shouldAck = true;
      d.ackPacket = ack;
    }
  }

  // ---- forwarding -----------------------------------------------------------
  if (forwardNeeded) {
    ++p.hop;
    if (p.path.empty() || p.path.back() != cfg_.myId) p.path.push_back(cfg_.myId);
    p.flags |= FLAG_RELAYED;
    --p.ttl;
    if (p.ttl < 0) {
      ++counters_.dropped;
      if (d.actions.empty()) d.actions.push_back(RouteAction::DROP);
      d.reason = "TTL_EXPIRED";
      return d;
    }
    ++counters_.forwarded;
    if (cfg_.loRaReachable) {
      // A LoRa peer was heard within ST_LORA_REACHABLE_WINDOW_MS → the node is
      // in LoRa range, so we use LoRa only (no BLE flood).
      if (cfg_.hasLoRa) d.actions.push_back(RouteAction::LORA_TX);
      if (destMe || clientHere) {
        d.reason = "loRa-reach+deliver";
      } else {
        d.reason = "loRa-reach";
      }
    } else {
      // No LoRa peer in range → flood LoRa (cheap, still dedup-cached) and BLE
      // so a multi-hop BLE mesh can carry the packet ("LoRa if in range, else
      // BLE with hopping").
      if (cfg_.hasLoRa) d.actions.push_back(RouteAction::LORA_TX);
      d.actions.push_back(RouteAction::BLE_TX);
      if (destMe || clientHere) {
        d.reason = "flood+deliver";
      } else {
        d.reason = "forward";
      }
    }
  } else {
    d.reason = "destination";
  }

  return d;
}

bool Router::ackFor(const Packet& p, Packet& out) const {
  out = makeAck(p, cfg_.myId, p.src, p.hop + 1);
  return true;
}

void Router::onAckSent(const std::string& mid, const std::string& device, long long nowMs) {
  store_.markAcked(mid, device, nowMs);
}

}  // namespace st