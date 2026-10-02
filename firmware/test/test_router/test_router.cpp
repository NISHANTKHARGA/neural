#include <Arduino.h>
#include <unity.h>

#include "core/packet.h"
#include "core/router.h"

using namespace st;

namespace {
// Injected clock.
long long nowMs = 1000000000LL;  // ~1e9 ms

Router makeRelay() {
  Router::Config c;
  c.myId = "N-A";
  c.isGateway = false;
  c.hasLoRa = true;
  c.maxAgeSec = 300;
  c.futureSkewSec = 60;
  c.seenTtlMs = 600000;
  return Router(c);
}

Router makeGateway() {
  Router::Config c;
  c.myId = "RCUE";
  c.isGateway = true;
  c.hasLoRa = true;
  c.maxAgeSec = 300;
  c.futureSkewSec = 60;
  c.seenTtlMs = 600000;
  return Router(c);
}

// Reset the shared clock for the next sub-test.
void bump() { nowMs += 1000; }
}  // namespace

static void test_gatewayDeliversSosAndAcks() {
  Router r = makeGateway();
  Packet sos = makeSos("T102", "27.9881", "86.925", "help", 8);
  sos.ts = nowMs / 1000;

  RouteDecision d = r.process(sos, "LoRa", nowMs, nowMs / 1000);
  TEST_ASSERT_TRUE(d.delivered);
  TEST_ASSERT_TRUE(d.shouldAck);
  TEST_ASSERT_EQUAL_STRING("ACK", d.ackPacket.type.c_str());
  TEST_ASSERT_EQUAL_STRING("RCUE", d.ackPacket.src.c_str());
  // SOS destined to the gateway: delivery only, no re-forward.
  bool hasLora = false, hasBle = false;
  for (auto a : d.actions) {
    if (a == RouteAction::LORA_TX) hasLora = true;
    if (a == RouteAction::BLE_TX) hasBle = true;
  }
  TEST_ASSERT_FALSE(hasLora);
  TEST_ASSERT_FALSE(hasBle);
  bump();
}

static void test_relayForwardsSosOverLoraAndBle() {
  Router r = makeRelay();
  Packet sos = makeSos("T102", "27.9881", "86.925", "help", 8);
  sos.ts = nowMs / 1000;

  RouteDecision d = r.process(sos, "BLE", nowMs, nowMs / 1000);
  TEST_ASSERT_FALSE(d.delivered);
  bool hasLora = false, hasBle = false;
  for (auto a : d.actions) {
    if (a == RouteAction::LORA_TX) hasLora = true;
    if (a == RouteAction::BLE_TX) hasBle = true;
  }
  TEST_ASSERT_TRUE(hasLora);
  TEST_ASSERT_TRUE(hasBle);
  TEST_ASSERT_EQUAL_INT(1, sos.hop);
  TEST_ASSERT_EQUAL_INT(7, sos.ttl);
  TEST_ASSERT_TRUE(sos.relayed());
  TEST_ASSERT_TRUE(sos.path.size() == 1 && sos.path[0] == "N-A");
  bump();
}

static void test_duplicateSuppression() {
  Router r = makeRelay();
  Packet sos = makeSos("T102", "1.0", "2.0", "dup", 8);
  sos.ts = nowMs / 1000;

  r.process(sos, "LoRa", nowMs, nowMs / 1000);
  Packet again = makeSos("T102", "1.0", "2.0", "dup", 8);
  again.mid = sos.mid;
  again.ts = nowMs / 1000;
  RouteDecision d2 = r.process(again, "BLE", nowMs, nowMs / 1000);
  TEST_ASSERT_TRUE(d2.actions.empty() || d2.actions[0] == RouteAction::DROP);
  TEST_ASSERT_TRUE(d2.actions.size() == 1 && d2.actions[0] == RouteAction::DROP);
  bump();
}

static void test_ttlExhaustionDrops() {
  Router r = makeRelay();
  Packet p = makeSos("T102", "1.0", "2.0", "x", 0);
  p.ts = nowMs / 1000;

  RouteDecision d = r.process(p, "LoRa", nowMs, nowMs / 1000);
  TEST_ASSERT_TRUE(d.actions.size() == 1 && d.actions[0] == RouteAction::DROP);
  TEST_ASSERT_EQUAL_STRING("TTL_EXPIRED", d.reason.c_str());
  bump();
}

static void test_stalePacketDropped() {
  Router r = makeRelay();
  Packet p = makeSos("T102", "1.0", "2.0", "old", 8);
  p.ts = nowMs / 1000 - 500;  // > maxAgeSec=300

  RouteDecision d = r.process(p, "LoRa", nowMs, nowMs / 1000);
  TEST_ASSERT_TRUE(d.actions.size() == 1 && d.actions[0] == RouteAction::DROP);
  TEST_ASSERT_EQUAL_STRING("STALE", d.reason.c_str());
  bump();
}

static void test_broadcastFloodsEverywhere() {
  Router r = makeGateway();
  Packet brd = makeBroadcast("RCUE", "FLASH FLOOD", "Avoid sector B", "U", 3, nowMs / 1000);

  RouteDecision d = r.process(brd, "app", nowMs, nowMs / 1000);
  TEST_ASSERT_TRUE(d.delivered);
  bool hasLora = false, hasBle = false, hasDeliver = false;
  for (auto a : d.actions) {
    if (a == RouteAction::LORA_TX) hasLora = true;
    if (a == RouteAction::BLE_TX) hasBle = true;
    if (a == RouteAction::DELIVER) hasDeliver = true;
  }
  TEST_ASSERT_TRUE(hasDeliver && hasLora && hasBle);
  bump();
}

static bool hookHasT5(const std::string& dst, void* ctx) {
  (void)ctx;
  return dst == "T5";
}

static void test_unicastDeliveredWhenClientAttached() {
  Router r = makeRelay();
  r.setClientHook(&hookHasT5, nullptr);

  Packet rescue = makeRescue("RCUE", "T5", 2, "Stay put", 8);
  rescue.ts = nowMs / 1000;

  RouteDecision d = r.process(rescue, "LoRa", nowMs, nowMs / 1000);
  TEST_ASSERT_TRUE(d.delivered);
  // Delivered locally → no forwarding actions.
  for (auto a : d.actions) {
    TEST_ASSERT_TRUE(a == RouteAction::DELIVER);
  }
  bump();
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_gatewayDeliversSosAndAcks);
  RUN_TEST(test_relayForwardsSosOverLoraAndBle);
  RUN_TEST(test_duplicateSuppression);
  RUN_TEST(test_ttlExhaustionDrops);
  RUN_TEST(test_stalePacketDropped);
  RUN_TEST(test_broadcastFloodsEverywhere);
  RUN_TEST(test_unicastDeliveredWhenClientAttached);
  UNITY_END();
}

void loop() { delay(100); }