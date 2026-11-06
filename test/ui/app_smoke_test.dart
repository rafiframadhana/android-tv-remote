import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_remote/core/device_store.dart';
import 'package:tv_remote/core/discovery.dart';
import 'package:tv_remote/core/identity_store.dart';
import 'package:tv_remote/core/share_service.dart';
import 'package:tv_remote/main.dart';
import 'package:tv_remote/ui/app_scope.dart';

/// Discovery without the platform plugin.
class _NoDiscovery extends TvDiscovery {
  @override
  Future<void> scan() async {}
}

void main() {
  testWidgets('first launch shows the TV list with add-by-IP', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final devices = DeviceStore();
    await devices.load();
    await tester.pumpWidget(
      TvRemoteApp(
        services: AppServices(
          identity: IdentityStore(),
          devices: devices,
          discovery: _NoDiscovery(),
          share: ShareService(devices: devices, identity: IdentityStore()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('TVs'), findsOneWidget);
    expect(find.text('Add by IP address'), findsOneWidget);
    expect(find.textContaining('No new TVs found'), findsOneWidget);
    expect(find.text('Search again'), findsOneWidget);

    await tester.tap(find.text('Add by IP address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not-an-ip');
    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await tester.pump();
    expect(find.text('Enter an address like 192.168.1.20'), findsOneWidget);
  });
}
