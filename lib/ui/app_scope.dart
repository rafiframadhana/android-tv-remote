import 'package:flutter/widgets.dart';

import '../core/app_settings.dart';
import '../core/device_store.dart';
import '../core/discovery.dart';
import '../core/identity_store.dart';
import '../core/share_service.dart';

/// App-wide services, created once in main().
class AppServices {
  AppServices({
    required this.identity,
    required this.devices,
    required this.discovery,
    required this.share,
    required this.settings,
  });
  final IdentityStore identity;
  final DeviceStore devices;
  final TvDiscovery discovery;

  /// Lets other phones join this phone's TV pairings (see core/share_link.dart).
  final ShareService share;

  /// Theme and remote shortcuts.
  final AppSettings settings;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
