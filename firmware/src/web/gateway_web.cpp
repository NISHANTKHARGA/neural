// GatewayWeb implementation — see gateway_web.h for the role overview.

#include "gateway_web.h"

#include <LittleFS.h>

namespace {

const char* kLogFile = "/incidents.log";

std::string packetEnvelope(const std::string& line) {
  return "{\"evt\":\"packet\",\"packet\":" + line + ",\"via\":\"gateway\"}";
}

}  // namespace

bool GatewayWeb::begin(const char* apSsid, const char* apPass, int channel,
                       uint16_t wsPort) {
  if (!LittleFS.begin(false)) {
    Serial.println("[web] LittleFS mount failed — formatting…");
    if (!LittleFS.begin(true)) {
      Serial.println("[web] LittleFS unavailable");
      return false;
    }
  }
  loadHistory();
  Serial.printf("[web] flash log: %u incidents cached\n",
                (unsigned)history_.size());

  WiFi.mode(WIFI_AP);
  if (!WiFi.softAP(apSsid, apPass, channel)) {
    Serial.println("[web] softAP failed");
    return false;
  }
  Serial.printf("[web] AP '%s' up — dashboard http://%s\n", apSsid,
                WiFi.softAPIP().toString().c_str());

  http_.on("/", [this] { serveFile("/www/index.html", "text/html"); });
  http_.on("/index.html", [this] { serveFile("/www/index.html", "text/html"); });
  http_.on("/style.css", [this] { serveFile("/www/style.css", "text/css"); });
  http_.on("/app.js", [this] {
    serveFile("/www/app.js", "application/javascript");
  });
  http_.on("/shared/packet.js", [this] {
    serveFile("/www/shared/packet.js", "application/javascript");
  });
  http_.onNotFound([this] {
    http_.send(404, "text/plain", "SAFETRAILS gateway — not found");
  });
  http_.begin();

  ws_ = WebSocketsServer(wsPort);
  ws_.onEvent([this](uint8_t num, WStype_t type, uint8_t* payload,
                     size_t length) { fire(ws_, num, type, payload, length); });
  ws_.begin();
  Serial.printf("[web] websocket hub on :%u\n", (unsigned)wsPort);
  return true;
}

void GatewayWeb::loop() {
  http_.handleClient();
  ws_.loop();
}

void GatewayWeb::onPacket(const std::string& jsonLine, bool persist) {
  if (persist) appendLog(jsonLine);
  String env = packetEnvelope(jsonLine).c_str();
  ws_.broadcastTXT(env);
}

void GatewayWeb::fire(WebSocketsServer&, uint8_t clientNum, WStype_t type,
                      uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      Serial.printf("[web] dashboard connected (#%u)\n", clientNum);
      {
        String hello = "{\"evt\":\"hello\",\"mode\":\"gateway-embedded\",\"serverTime\":" +
                       String((unsigned long)millis()) + "}";
        ws_.sendTXT(clientNum, hello);
      }
      replayTo(clientNum);
      break;
    case WStype_TEXT: {
      std::string msg((const char*)payload, length);
      if (!msg.empty() && msg[0] == '{' && onCommand) onCommand(msg);
      break;
    }
    case WStype_DISCONNECTED:
      Serial.printf("[web] dashboard disconnected (#%u)\n", clientNum);
      break;
    default:
      break;
  }
}

void GatewayWeb::serveFile(const char* fsPath, const char* mime) {
  File f = LittleFS.open(fsPath, "r");
  if (!f) {
    http_.send(404, "text/plain", String(fsPath) + " missing — reflash FS");
    return;
  }
  http_.streamFile(f, mime);
  f.close();
}

void GatewayWeb::loadHistory() {
  history_.clear();
  File f = LittleFS.open(kLogFile, "r");
  if (!f) return;
  size_t consumed = 0;
  std::vector<std::string> all;
  char buf[512];
  size_t n = 0;
  while ((n = f.readBytesUntil('\n', buf, sizeof(buf) - 1)) > 0) {
    buf[n] = '\0';
    consumed += n + 1;
    std::string line(buf);
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (!line.empty()) all.push_back(line);
  }
  f.close();
  // Keep the newest messages when the log grew large.
  const size_t keep = (consumed > logMax_) ? historyCap_ : all.size();
  const size_t start = (all.size() > keep) ? all.size() - keep : 0;
  for (size_t i = start; i < all.size(); i++) history_.push_back(all[i]);
}

void GatewayWeb::appendLog(const std::string& line) {
  if (!history_.empty() && history_.back() == line) return;  // de-dup adjacency
  history_.push_back(line);
  if (history_.size() > historyCap_) {
    history_.erase(history_.begin(), history_.begin() + (history_.size() - historyCap_));
  }

  File f = LittleFS.open(kLogFile, "r");
  const bool oversized = f && f.size() > logMax_;
  f.close();
  if (oversized) {
    // Rotate: rewrite the log from the in-RAM tail we still care about.
    File g = LittleFS.open(kLogFile, "w");
    if (g) {
      for (size_t i = 0; i < history_.size(); i++) {
        g.print(history_[i].c_str());
        g.print('\n');
      }
      g.close();
    }
  }
  File a = LittleFS.open(kLogFile, "a");
  if (a) {
    a.print(line.c_str());
    a.print('\n');
    a.close();
  }
}

void GatewayWeb::replayTo(uint8_t clientNum) {
  for (size_t i = 0; i < history_.size(); i++) {
    String env = packetEnvelope(history_[i]).c_str();
    ws_.sendTXT(clientNum, env);
  }
  Serial.printf("[web] replayed %u cached incidents to #%u\n",
                (unsigned)history_.size(), clientNum);
}