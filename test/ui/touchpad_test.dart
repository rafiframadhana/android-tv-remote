import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/tv_connection.dart';
import 'package:tv_remote/protocol/key_codes.dart';
import 'package:tv_remote/protocol/remote_messages.dart';
import 'package:tv_remote/ui/widgets/dpad.dart';
import 'package:tv_remote/ui/widgets/remote_key.dart';

/// Records the keys sent instead of talking to a TV.
class _FakeConn extends ChangeNotifier implements TvConnection {
  final sent = <(int, KeyDirection)>[];

  @override
  bool get isConnected => true;

  @override
  void sendKey(int keyCode, [KeyDirection direction = KeyDirection.short]) => sent.add((keyCode, direction));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeConn conn;
  late ScrollController scroll;

  Future<void> pumpPad(WidgetTester tester) async {
    conn = _FakeConn();
    scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: RemoteScope(
          connection: conn,
          child: SingleChildScrollView(
            controller: scroll,
            child: const Column(
              children: [
                SizedBox(key: Key('spacer'), height: 200),
                Touchpad(size: 260),
                SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<int> codes() => conn.sent.map((s) => s.$1).toList();

  /// Moves a finger in small steps, like a real swipe.
  Future<void> swipe(WidgetTester tester, Finder f, Offset by, {Offset? from}) async {
    final g = await tester.startGesture(from ?? tester.getCenter(f));
    const steps = 30;
    for (var i = 0; i < steps; i++) {
      await g.moveBy(by / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('vertical swipe sends Up and does not scroll the page', (tester) async {
    await pumpPad(tester);
    await swipe(tester, find.byType(Touchpad), const Offset(0, -120));
    expect(codes(), [Keys.dpadUp, Keys.dpadUp, Keys.dpadUp]);
    expect(scroll.offset, 0);
  });

  testWidgets('downward swipe sends Down', (tester) async {
    await pumpPad(tester);
    await swipe(tester, find.byType(Touchpad), const Offset(0, 80));
    expect(codes(), [Keys.dpadDown, Keys.dpadDown]);
    expect(scroll.offset, 0);
  });

  testWidgets('horizontal swipe sends Right', (tester) async {
    await pumpPad(tester);
    await swipe(tester, find.byType(Touchpad), const Offset(80, 0));
    expect(codes(), [Keys.dpadRight, Keys.dpadRight]);
  });

  testWidgets('tap sends a single OK', (tester) async {
    await pumpPad(tester);
    await tester.tap(find.byType(Touchpad));
    await tester.pumpAndSettle();
    expect(conn.sent, [(Keys.dpadCenter, KeyDirection.short)]);
  });

  testWidgets('long-press sends a long OK', (tester) async {
    await pumpPad(tester);
    final g = await tester.startGesture(tester.getCenter(find.byType(Touchpad)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.up();
    await tester.pumpAndSettle();
    expect(conn.sent, [(Keys.dpadCenter, KeyDirection.startLong), (Keys.dpadCenter, KeyDirection.endLong)]);
  });

  testWidgets('dragging outside the pad still scrolls the page', (tester) async {
    await pumpPad(tester);
    await swipe(tester, find.byKey(const Key('spacer')), const Offset(0, -150), from: const Offset(400, 100));
    expect(scroll.offset, greaterThan(0));
    expect(conn.sent, isEmpty);
  });
}
