import 'package:flutter_test/flutter_test.dart';

import 'package:safetrails/link/link_controller.dart';
import 'package:safetrails/state/sos_controller.dart';

void main() {
  testWidgets('SAFETRAILS app builds', (WidgetTester tester) async {
    expect(SosState.values.length, greaterThanOrEqualTo(9));
    expect(LinkTransport.values.length, 4);
  });
}