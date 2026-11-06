import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_remote/core/app_settings.dart';
import 'package:tv_remote/core/device_store.dart';
import 'package:tv_remote/core/discovery.dart';
import 'package:tv_remote/core/identity_store.dart';
import 'package:tv_remote/core/share_service.dart';
import 'package:tv_remote/main.dart';
import 'package:tv_remote/ui/app_scope.dart';
import 'package:tv_remote/ui/shortcuts/catalog.dart';
import 'package:tv_remote/ui/theme.dart';

class _NoDiscovery extends TvDiscovery {
  @override
  Future<void> scan() async {}
}

void main() {
  group('shortcut catalogue', () {
    test('ids are unique and defaults exist', () {
      final ids = shortcutCatalog.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in defaultShortcutIds) {
        expect(ids, contains(id));
      }
    });

    test('every entry can be opened: a link, a store fallback, or an explicit template', () {
      for (final s in shortcutCatalog) {
        expect(s.package, isNotEmpty, reason: s.id);
        expect(s.link.isNotEmpty || s.storeFallback || s.template, isTrue, reason: s.id);
        expect(s.link.startsWith('intent:'), isFalse, reason: '${s.id}: the TV does not accept intent: URIs');
      }
    });

    test('BitTV sits right after Play Store and uses its bundled icon', () {
      final ids = shortcutCatalog.map((s) => s.id).toList();
      expect(ids.indexOf('bittv'), ids.indexOf('playstore') + 1);
      expect(shortcutCatalog.firstWhere((s) => s.id == 'bittv').icon, isA<AssetIcon>());
    });

    test('initials', () {
      expect(initials('Living Room TV'), 'LR');
      expect(initials('kodi'), 'K');
      expect(initials('  '), '?');
    });
  });

  group('AppSettings', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('first run: system theme and the four default shortcuts', () async {
      final s = AppSettings();
      await s.load();
      expect(s.themeMode, ThemeMode.system);
      expect(s.enabledIds, defaultShortcutIds);
    });

    test('enable appends, disable removes, move reorders, all persisted', () async {
      final s = AppSettings();
      await s.load();
      await s.setEnabled('playstore', true);
      await s.setEnabled('bittv', true);
      await s.setEnabled('netflix', false);
      await s.moveEnabled(3, 0); // playstore to the front
      await s.setThemeMode(ThemeMode.light);
      expect(s.enabledIds, ['playstore', 'youtube', 'primevideo', 'disneyplus', 'bittv']);

      final again = AppSettings();
      await again.load();
      expect(again.enabledIds, s.enabledIds);
      expect(again.themeMode, ThemeMode.light);
    });

    test('unknown saved ids are dropped', () async {
      SharedPreferences.setMockInitialValues({
        'shortcuts_v1': ['youtube', 'removed-app', 'netflix'],
      });
      final s = AppSettings();
      await s.load();
      expect(s.enabledIds, ['youtube', 'netflix']);
    });

    test('link override replaces a link and can be reset', () async {
      final s = AppSettings();
      await s.load();
      TvShortcut bittv() => s.allShortcuts.firstWhere((x) => x.id == 'bittv');
      expect(bittv().link, 'tv://');
      await s.setLinkOverride('bittv', 'channel://');
      expect(bittv().link, 'channel://');
      expect(s.hasLinkOverride('bittv'), isTrue);
      await s.setLinkOverride('bittv', '');
      expect(bittv().link, 'tv://');
    });

    test('a store-fallback entry given a link stops using the store', () async {
      final s = AppSettings();
      await s.load();
      TvShortcut kodi() => s.allShortcuts.firstWhere((x) => x.id == 'kodi');
      expect(kodi().storeFallback, isTrue);
      await s.setLinkOverride('kodi', 'kodi://');
      expect(kodi().storeFallback, isFalse);
    });

    test('custom apps are added enabled and can be removed', () async {
      final s = AppSettings();
      await s.load();
      final id = await s.addCustom('My App', 'myapp://');
      expect(s.enabledShortcuts.last.name, 'My App');
      final again = AppSettings();
      await again.load();
      expect(again.enabledIds, contains(id));
      await again.removeCustom(id);
      expect(again.allShortcuts.any((x) => x.id == id), isFalse);
      expect(again.enabledIds, isNot(contains(id)));
    });
  });

  group('Settings UI', () {
    Future<AppSettings> pumpApp(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final devices = DeviceStore();
      await devices.load();
      final settings = AppSettings();
      await settings.load();
      await tester.pumpWidget(
        TvRemoteApp(
          services: AppServices(
            identity: IdentityStore(),
            devices: devices,
            discovery: _NoDiscovery(),
            share: ShareService(devices: devices, identity: IdentityStore()),
            settings: settings,
          ),
        ),
      );
      await tester.pump();
      return settings;
    }

    testWidgets('gear opens Settings; Shortcuts lists defaults and turning one on adds it', (tester) async {
      final settings = await pumpApp(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('4 apps on your remote'), findsOneWidget);

      await tester.tap(find.text('Shortcuts'));
      await tester.pumpAndSettle();
      expect(find.text('On your remote'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'play');
      await tester.pumpAndSettle();
      final playRow = find.ancestor(of: find.text('Play Store'), matching: find.byType(ListTile));
      await tester.tap(find.descendant(of: playRow, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(settings.enabledIds.last, 'playstore');
    });

    testWidgets('theme switch changes the app colours', (tester) async {
      final settings = await pumpApp(tester);
      await settings.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      final dark = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(Theme.of(tester.element(find.byWidget(dark))).scaffoldBackgroundColor, RemotePalette.dark.body);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.light);
      expect(Theme.of(tester.element(find.text('Theme'))).extension<RemotePalette>()!.body, RemotePalette.light.body);
    });
  });
}
