#pragma once

#include <cstdint>
#include <string>
#include <vector>

// --------------------------------------------------------------------------
// SAFETRAILS packet — shared core.
// Host-testable: does NOT depend on Arduino / ESP32 APIs.
// Mirrors shared/protocol/packet.js and shared/protocol/dart/lib/packet.dart
// (checksums must be byte-identical across platforms).
// --------------------------------------------------------------------------

namespace st {

constexpr int FLAG_ACK_REQUIRED = 1;
constexpr int FLAG_ACKED = 2;
constexpr int FLAG_RELAYED = 4;
constexpr int FLAG_BROADCAST = 8;

constexpr const char* NO_VALUE = "-";
constexpr int MAX_COORD_DECIMALS = 6;
constexpr int MAX_BODY_COMPACT = 120;
constexpr int MAX_BODY_JSON = 200;

struct Packet {
  int version = 1;
  std::string type;              // SOS ACK RESCUE BROAD STATUS TRACK PING PONG
  int prio = 0;                  // 0..3
  std::string mid;               // 1..16 alnum
  std::string src;               // 1..16 [A-Za-z0-9_]
  std::string dst;               // 1..16 or "*"
  std::string lat;               // verbatim decimal or "-"
  std::string lon;               // verbatim decimal or "-"
  long long ts = 0;              // unix seconds
  int hop = 0;                   // 0..15
  int ttl = 8;                   // 0..15
  int flags = 0;                 // bitmask
  std::vector<std::string> path; // traversed node ids (reverse route)
  std::string ck;                // 4 hex chars
  std::string body;

  bool valid = true;
  std::string invalidReason;

  bool isBroadcast() const { return (flags & FLAG_BROADCAST) || dst == "*"; }
  bool ackRequired() const { return flags & FLAG_ACK_REQUIRED; }
  bool acked() const { return flags & FLAG_ACKED; }
  bool relayed() const { return flags & FLAG_RELAYED; }
};

// ---- utilities -------------------------------------------------------------

inline std::string trim(const std::string& s) {
  size_t a = s.find_first_not_of(" \t\r\n");
  if (a == std::string::npos) return "";
  size_t b = s.find_last_not_of(" \t\r\n");
  return s.substr(a, b - a + 1);
}

std::string sanitizeToken(const std::string& s, size_t max, const char* allowed);

// Identify-normalization shared by all platforms.
std::string normalizeCoord(const std::string& s);
std::string coordFrom(const std::string& s);

// FNV-1a 32-bit reduced to low 16 bits, 4 lowercase hex chars.
std::string fnv1a16(const std::string& text);

// Canonical `|`-joined field string over which the checksum is computed.
std::string canonicalFields(const Packet& p);

// ---- JSON codec (BLE / serial / host) --------------------------------------

// Parses our minimal JSON packet. Sets p.valid=false + invalidReason on error.
// NOTE: performs the same input sanitisation as buildPacket() in JS/Dart.
Packet parseJson(const std::string& json);

// Renders canonical JSON for a (possibly unsanitised) packet.
std::string toJson(const Packet& p);

// ---- Compact codec (LoRa) ---------------------------------------------------

// Encodes a compact `|`-delimited frame, truncating body to fit maxBody.
std::string toCompact(const Packet& p, size_t maxBody = MAX_BODY_COMPACT);

// Parses + validates a compact frame (checksum included).
Packet parseCompact(const std::string& frame);

// ---- factories --------------------------------------------------------------

Packet makeSos(const std::string& touristId, const std::string& lat,
               const std::string& lon, const std::string& body, int ttl = 8);

Packet makeRescue(const std::string& from, const std::string& dst, int prio,
                  const std::string& body, int ttl = 8);

Packet makeAck(const Packet& original, const std::string& from, const std::string& dst,
               int ttl = 8);

Packet makeBroadcast(const std::string& from, const std::string& title,
                     const std::string& message, const std::string& area,
                     int prio, long long ts);

}  // namespace st