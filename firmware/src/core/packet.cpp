#include "packet.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <map>

namespace st {

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

static bool isIdentChar(char c) {
  return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
         c == '_' || c == '*' || c == ',';
}

std::string sanitizeToken(const std::string& s, size_t max, const char* allowed) {
  std::string out;
  out.reserve(s.size());
  for (char c : s) {
    if (strchr(allowed, c)) out.push_back(c);
  }
  if (out.size() > max) out = out.substr(0, max);
  return out;
}

std::string normalizeCoord(const std::string& s) {
  std::string t = trim(s);
  if (t.empty() || t == NO_VALUE) return NO_VALUE;
  size_t dot = t.find('.');
  if (dot == std::string::npos) return t;
  std::string frac = t.substr(dot + 1);
  if (frac.size() > static_cast<size_t>(MAX_COORD_DECIMALS)) {
    frac = frac.substr(0, MAX_COORD_DECIMALS);
  }
  size_t end = frac.find_last_not_of('0');
  if (end == std::string::npos) return t.substr(0, dot);
  frac = frac.substr(0, end + 1);
  return t.substr(0, dot + 1) + frac;
}

std::string coordFrom(const std::string& s) {
  std::string t = trim(s);
  return (t.empty() || t == NO_VALUE) ? NO_VALUE : t;
}

std::string fnv1a16(const std::string& text) {
  uint32_t h = 0x811c9dc5u;
  for (unsigned char c : text) {
    h ^= c;
    h = (h * 0x01000193u) & 0xffffffffu;
  }
  uint32_t v = (h >> 16) & 0xffffu;
  char buf[8];
  snprintf(buf, sizeof(buf), "%04x", v);
  return buf;
}

std::string canonicalFields(const Packet& p) {
  std::string path = NO_VALUE;
  if (!p.path.empty()) {
    path = "";
    for (size_t i = 0; i < p.path.size(); ++i) {
      if (i) path += ',';
      path += p.path[i];
    }
  }

  std::string out = "ST";
  out += '|'; out += std::to_string(p.version);
  out += '|'; out += p.type;
  out += '|'; out += std::to_string(p.prio);
  out += '|'; out += p.mid;
  out += '|'; out += p.src;
  out += '|'; out += p.dst;
  out += '|'; out += normalizeCoord(p.lat);
  out += '|'; out += normalizeCoord(p.lon);
  out += '|'; out += std::to_string(p.ts);
  out += '|'; out += std::to_string(p.hop);
  out += '|'; out += std::to_string(p.ttl);
  out += '|'; out += std::to_string(p.flags);
  out += '|'; out += path;
  return out;
}

// ---------------------------------------------------------------------------
// minimal JSON support (our schema only)
// ---------------------------------------------------------------------------

namespace json {
enum class Kind { STR, NUM, ARR, OBJ, NUL };

struct Val {
  Kind kind = Kind::NUL;
  std::string text;                // STR: unescaped / NUM: verbatim / NUL: null
  std::vector<std::string> arr;    // ARR
  std::map<std::string, Val> obj;  // OBJ
};

static std::string unescape(const std::string& s, size_t& i) {
  std::string out;
  while (i < s.size()) {
    char c = s[i++];
    if (c == '"') break;
    if (c == '\\' && i < s.size()) {
      char e = s[i++];
      switch (e) {
        case 'n': out += '\n'; break;
        case 't': out += '\t'; break;
        case 'r': out += '\r'; break;
        case 'b': out += '\b'; break;
        case 'f': out += '\f'; break;
        case '/': out += '/'; break;
        case '\\': out += '\\'; break;
        case '"': out += '"'; break;
        case 'u': {
          if (i + 4 <= s.size()) {
            out += "\\u"; out += s.substr(i, 4);
            i += 4;
          }
          break;
        }
        default: out += e; break;
      }
    } else {
      out += c;
    }
  }
  return out;
}

static void skipWs(const std::string& s, size_t& i) {
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) i++;
}

static Val parseValue(const std::string& s, size_t& i) {
  skipWs(s, i);
  Val v;
  if (i >= s.size()) return v;
  char c = s[i];
  if (c == '"') {
    i++;
    v.kind = Kind::STR;
    v.text = unescape(s, i);
  } else if (c == '[') {
    v.kind = Kind::ARR;
    i++;
    skipWs(s, i);
    if (i < s.size() && s[i] == ']') { i++; return v; }
    while (i < s.size()) {
      Val el = parseValue(s, i);
      if (el.kind == Kind::STR) v.arr.push_back(el.text);
      skipWs(s, i);
      if (i < s.size() && s[i] == ',') { i++; continue; }
      if (i < s.size() && s[i] == ']') { i++; break; }
      break;
    }
  } else if (c == '{') {
    v.kind = Kind::OBJ;
    i++;
    skipWs(s, i);
    if (i < s.size() && s[i] == '}') { i++; return v; }
    while (i < s.size()) {
      skipWs(s, i);
      if (s[i] == '"') {
        i++;
        std::string key = unescape(s, i);
        skipWs(s, i);
        if (i < s.size() && s[i] == ':') i++;
        v.obj[key] = parseValue(s, i);
      }
      skipWs(s, i);
      if (i < s.size() && s[i] == ',') { i++; continue; }
      if (i < s.size() && s[i] == '}') { i++; break; }
      break;
    }
  } else if (c == '-' || (c >= '0' && c <= '9')) {
    v.kind = Kind::NUM;
    size_t start = i;
    while (i < s.size()) {
      char d = s[i];
      if ((d >= '0' && d <= '9') || d == '.' || d == '-' || d == '+' || d == 'e' || d == 'E') {
        i++;
      } else {
        break;
      }
    }
    v.text = s.substr(start, i - start);
  } else if (c == 't') {
    if (s.compare(i, 4, "true") == 0) { v.kind = Kind::NUM; v.text = "1"; i += 4; }
  } else if (c == 'f') {
    if (s.compare(i, 5, "false") == 0) { v.kind = Kind::NUM; v.text = "0"; i += 5; }
  } else if (c == 'n') {
    if (s.compare(i, 4, "null") == 0) { i += 4; }
  }
  return v;
}

static Val parseObject(const std::string& s) {
  size_t i = 0;
  Val root = parseValue(s, i);
  if (root.kind != Kind::OBJ) root = Val();
  return root;
}
}  // namespace json

// ---------------------------------------------------------------------------
// JSON packet codec
// ---------------------------------------------------------------------------

static long long toLL(const std::string& s) {
  if (s.empty()) return 0;
  return strtoll(s.c_str(), nullptr, 10);
}
static int toInt(const std::string& s) {
  if (s.empty()) return 0;
  return atoi(s.c_str());
}

static bool knownType(const std::string& t) {
  return t == "SOS" || t == "ACK" || t == "RESCUE" || t == "BROAD" || t == "STATUS" ||
         t == "TRACK" || t == "PING" || t == "PONG";
}

static void normalize(Packet& p) {
  p.type = sanitizeToken(p.type, 16, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
  p.mid = sanitizeToken(p.mid, 16, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-");
  p.src = sanitizeToken(p.src, 16, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-");
  std::string dst = sanitizeToken(p.dst, 16, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_*-");
  p.dst = dst.empty() ? "*" : dst;
  p.lat = normalizeCoord(p.lat);
  p.lon = normalizeCoord(p.lon);
  if (p.hop < 0) p.hop = 0;
  if (p.hop > 15) p.hop = 15;
  if (p.ttl < 0) p.ttl = 0;
  if (p.ttl > 15) p.ttl = 15;
  p.flags &= 0x0f;
  for (auto& x : p.path) {
    x = sanitizeToken(x, 16, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-,");
  }
  if (p.body.size() > static_cast<size_t>(MAX_BODY_JSON)) {
    p.body = p.body.substr(0, MAX_BODY_JSON);
  }
  // strip CR/LF from body like JS buildPacket
  std::string clean;
  clean.reserve(p.body.size());
  for (char c : p.body) {
    if (c != '\n' && c != '\r') clean.push_back(c);
  }
  p.body = clean;
  p.ck = fnv1a16(canonicalFields(p));
}

static std::string jsonEscape(const std::string& s) {
  std::string out;
  out.reserve(s.size() + 8);
  for (char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          char buf[8];
          snprintf(buf, sizeof(buf), "\\u%04x", (unsigned char)c);
          out += buf;
        } else {
          out += c;
        }
    }
  }
  return out;
}

static std::string jsonNumOrDash(const std::string& v) {
  // Always quoted — matches the JS and Dart JSON writers ("lat":"27.9881").
  return std::string("\"") + (v == NO_VALUE ? std::string(NO_VALUE) : v) + "\"";
}

std::string toJson(const Packet& pIn) {
  Packet p = pIn;
  normalize(p);
  std::string out = "{";
  out += "\"v\":" + std::to_string(p.version);
  out += ",\"type\":\"" + jsonEscape(p.type) + "\"";
  out += ",\"prio\":" + std::to_string(p.prio);
  out += ",\"mid\":\"" + jsonEscape(p.mid) + "\"";
  out += ",\"src\":\"" + jsonEscape(p.src) + "\"";
  out += ",\"dst\":\"" + jsonEscape(p.dst) + "\"";
  out += ",\"lat\":" + jsonNumOrDash(p.lat);
  out += ",\"lon\":" + jsonNumOrDash(p.lon);
  out += ",\"ts\":" + std::to_string(p.ts);
  out += ",\"hop\":" + std::to_string(p.hop);
  out += ",\"ttl\":" + std::to_string(p.ttl);
  out += ",\"flags\":" + std::to_string(p.flags);
  out += ",\"path\":[";
  for (size_t i = 0; i < p.path.size(); ++i) {
    if (i) out += ',';
    out += '\"' + jsonEscape(p.path[i]) + '\"';
  }
  out += "]";
  out += ",\"ck\":\"" + p.ck + "\"";
  out += ",\"body\":\"" + jsonEscape(p.body) + "\"";
  out += "}";
  return out;
}

Packet parseJson(const std::string& line) {
  Packet p;
  const json::Val root = json::parseObject(line);
  if (root.kind != json::Kind::OBJ) {
    p.valid = false;
    p.invalidReason = "BAD_PACKET";
    return p;
  }
  const auto& o = root.obj;
  auto str = [&](const char* key, const std::string& dflt) {
    auto it = o.find(key);
    if (it != o.end() && it->second.kind == json::Kind::STR) return it->second.text;
    if (it != o.end() && it->second.kind == json::Kind::NUM) return it->second.text;
    return dflt;
  };
  auto num = [&](const char* key) -> std::string {
    auto it = o.find(key);
    if (it != o.end() && (it->second.kind == json::Kind::NUM || it->second.kind == json::Kind::STR)) {
      return it->second.text;
    }
    return NO_VALUE;
  };
  auto numI = [&](const char* key, int dflt) {
    auto it = o.find(key);
    return it != o.end() ? toInt(it->second.text) : dflt;
  };
  auto numLL = [&](const char* key, long long dflt) {
    auto it = o.find(key);
    return it != o.end() ? toLL(it->second.text) : dflt;
  };

  p.version = numI("v", 1);
  p.type = str("type", "");
  p.prio = numI("prio", 0);
  p.mid = str("mid", "");
  p.src = str("src", "");
  p.dst = str("dst", "*");
  p.lat = num("lat");
  p.lon = num("lon");
  p.ts = numLL("ts", 0);
  p.hop = numI("hop", 0);
  p.ttl = numI("ttl", 8);
  p.flags = numI("flags", 0);
  p.path.clear();
  auto it = o.find("path");
  if (it != o.end() && it->second.kind == json::Kind::ARR) {
    for (const auto& e : it->second.arr) p.path.push_back(e);
  }
  p.ck = str("ck", "");
  p.body = str("body", "");

  normalize(p);

  if (p.version != 1) { p.valid = false; p.invalidReason = "BAD_VERSION"; return p; }
  if (!knownType(p.type)) { p.valid = false; p.invalidReason = "UNKNOWN_TYPE"; return p; }
  if (p.mid.empty() || p.src.empty()) { p.valid = false; p.invalidReason = "MISSING_ID"; return p; }
  if (!p.ck.empty() && p.ck != fnv1a16(canonicalFields(p))) {
    p.valid = false;
    p.invalidReason = "BAD_CHECKSUM";
    return p;
  }
  return p;
}

// ---------------------------------------------------------------------------
// Compact codec
// ---------------------------------------------------------------------------

std::string toCompact(const Packet& pIn, size_t maxBody) {
  Packet p = pIn;
  normalize(p);
  std::string body;
  body.reserve(p.body.size());
  for (char c : p.body) {
    if (c == '|') {
      body += ';';
    } else if (c != '\n' && c != '\r') {
      body += c;
    }
  }
  if (body.size() > maxBody) body = body.substr(0, maxBody);
  const std::string frame = canonicalFields(p);
  const std::string ck = fnv1a16(frame);
  return frame + "|" + ck + "|" + body;
}

Packet parseCompact(const std::string& frame) {
  Packet p;
  // split preserving empties; simplest scan
  std::vector<std::string> f;
  size_t start = 0;
  for (size_t i = 0; i <= frame.size(); ++i) {
    if (i == frame.size() || frame[i] == '|') {
      f.push_back(frame.substr(start, i - start));
      start = i + 1;
    }
  }
  if (f.size() < 15 || f[0] != "ST") { p.valid = false; p.invalidReason = "INVALID"; return p; }
  if (f[1] != "1") { p.valid = false; p.invalidReason = "BAD_VERSION"; return p; }

  // recompute checksum over fields 0..13
  std::string frameForCk;
  for (int i = 0; i < 14; ++i) {
    if (i) frameForCk += '|';
    frameForCk += f[i];
  }
  if (fnv1a16(frameForCk) != f[14]) { p.valid = false; p.invalidReason = "BAD_CHECKSUM"; return p; }

  p.version = 1;
  p.type = f[2];
  p.prio = toInt(f[3]);
  p.mid = f[4];
  p.src = f[5];
  p.dst = f[6];
  p.lat = coordFrom(f[7]);
  p.lon = coordFrom(f[8]);
  p.ts = toLL(f[9]);
  p.hop = toInt(f[10]);
  p.ttl = toInt(f[11]);
  p.flags = toInt(f[12]);
  p.path.clear();
  if (f[13] != NO_VALUE) {
    std::string acc;
    for (char c : f[13]) {
      if (c == ',') { p.path.push_back(acc); acc.clear(); } else { acc += c; }
    }
    if (!acc.empty()) p.path.push_back(acc);
  }
  p.ck = f[14];
  // body = every field after 14 rejoined (should not contain '|')
  for (size_t i = 15; i < f.size(); ++i) {
    if (i > 15) p.body += '|';
    p.body += f[i];
  }

  if (!knownType(p.type)) { p.valid = false; p.invalidReason = "UNKNOWN_TYPE"; return p; }
  if (p.mid.empty() || p.src.empty()) { p.valid = false; p.invalidReason = "MISSING_ID"; return p; }
  return p;
}

// ---------------------------------------------------------------------------
// factories
// ---------------------------------------------------------------------------

static std::string newMid(const char* prefix) {
  static unsigned long counter = 0;
  unsigned long c = (counter = (counter + 1) & 0xffffff);
  unsigned long t = (unsigned long)(time(nullptr) & 0xffff);
  char buf[32];
  snprintf(buf, sizeof(buf), "%s-%02lx%06lx", prefix, t, c);
  return buf;
}

Packet makeSos(const std::string& touristId, const std::string& lat,
               const std::string& lon, const std::string& body, int ttl) {
  Packet p;
  p.type = "SOS";
  p.prio = 3;
  p.mid = newMid("SOS");
  p.src = touristId;
  p.dst = "RCUE";
  p.lat = coordFrom(lat);
  p.lon = coordFrom(lon);
  p.ts = (long long)time(nullptr);
  p.hop = 0;
  p.ttl = ttl;
  p.flags = FLAG_ACK_REQUIRED;
  p.body = body;
  normalize(p);
  return p;
}

Packet makeAck(const Packet& original, const std::string& from, const std::string& dst, int ttl) {
  Packet p;
  p.type = "ACK";
  p.prio = original.prio;
  p.mid = "ACK-" + original.mid;
  p.src = from;
  p.dst = dst.empty() ? original.src : dst;
  p.ts = (long long)time(nullptr);
  p.hop = 0;
  p.ttl = ttl;
  p.flags = 0;
  p.body = original.mid;  // correlate
  normalize(p);
  return p;
}

Packet makeRescue(const std::string& from, const std::string& dst, int prio,
                  const std::string& body, int ttl) {
  Packet p;
  p.type = "RESCUE";
  p.prio = prio > 3 ? 3 : (prio < 0 ? 0 : prio);
  p.mid = newMid("RSC");
  p.src = from;
  p.dst = dst;
  p.ts = (long long)time(nullptr);
  p.hop = 0;
  p.ttl = ttl;
  p.flags = 0;
  p.body = body;
  normalize(p);
  return p;
}

Packet makeBroadcast(const std::string& from, const std::string& title,
                     const std::string& message, const std::string& area, int prio,
                     long long ts) {
  Packet p;
  p.type = "BROAD";
  p.prio = prio > 3 ? 3 : (prio < 0 ? 0 : prio);
  p.mid = newMid("BRD");
  p.src = from;
  p.dst = "*";
  p.ts = ts ? ts : (long long)time(nullptr);
  p.hop = 0;
  p.ttl = 12;
  p.flags = FLAG_BROADCAST;
  p.body = title + "^" + message + "^" + area;
  normalize(p);
  return p;
}

}  // namespace st