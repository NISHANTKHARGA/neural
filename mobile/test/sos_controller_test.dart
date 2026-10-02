import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetrails_protocol/packet.dart';

import 'package:safetrails/state/sos_controller.dart';

class FakeRelay {
  bool connected = false;
  bool sendResult = true;
  final inbound = StreamController<Packet>.broadcast();
  final List<Packet> sent = [];

  Future<void> connectAndListen() async {
    connected = true;
  }

  Future<bool> sendSos(Packet p) async {
    sent.add(p);
    return sendResult;
  }

  void push(Packet p) => inbound.add(p);
}

class FakeGps {
  final Position? position;
  final Position? last;

  FakeGps({this.position, this.last});
  Future<Position?> getPosition() async => position;
}

class Position {
  const Position(this.latitude, this.longitude);
  final num latitude;
  final num longitude;
}

void main() {
  test('SOS flow: CREATED -> BLE_SENT -> ACKNOWLEDGED', () async {
    final relay = FakeRelay();
    final gps = FakeGps(position: const Position(27.9881, 86.925));
    final controller = SosController(relay: relay, gps: gps);
    controller.watchInbound(relay.inbound.stream);

    final ok = await controller.sendSos(body: 'please help');
    expect(ok, isTrue);
    expect(relay.sent, hasLength(1));
    expect(controller.active, isNotNull);
    expect(controller.active!.status, SosState.bleSent);
    expect(controller.active!.packet.lat, '27.9881');

    // Rescue gateway ACKs; the ACK body carries our original mid.
    final ack = PacketFactory.ackFor(controller.active!.packet);
    relay.push(ack);
    await Future<void>.delayed(Duration.zero); // let broadcast stream deliver

    expect(controller.active!.status, SosState.acknowledged);
    controller.dispose();
    await relay.inbound.close();
  });

  test('SOS retries then FAILED when write never succeeds', () async {
    final relay = FakeRelay()..sendResult = false;
    final controller = SosController(relay: relay, gps: FakeGps());
    final ok = await controller.sendSos();
    expect(ok, isFalse);
    expect(controller.active, isNull); // cleared after failure
    expect(controller.messages.first.status, SosState.failed);
    controller.dispose();
  });

  test('missing GPS produces noValue coordinates instead of error', () async {
    final relay = FakeRelay();
    final controller = SosController(relay: relay, gps: FakeGps());
    await controller.sendSos();
    final p = relay.sent.single;
    expect(p.lat, Packet.noValue);
    expect(p.lon, Packet.noValue);
    controller.dispose();
  });

  test('SOS falls back to last known position when fresh fix fails', () async {
    final relay = FakeRelay();
    final controller = SosController(
      relay: relay,
      gps: FakeGps(last: const Position(27.9881, 86.925)),
    );
    await controller.sendSos();
    final p = relay.sent.single;
    expect(p.lat, '27.9881');
    expect(p.lon, '86.925');
    controller.dispose();
  });
}