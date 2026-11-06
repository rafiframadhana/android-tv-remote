import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/device_store.dart';
import 'core/discovery.dart';
import 'core/identity_store.dart';
import 'core/share_service.dart';
import 'ui/app_scope.dart';
import 'ui/devices_screen.dart';
import 'ui/remote_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final devices = DeviceStore();
  await devices.load();
  final identity = IdentityStore();
  final services = AppServices(
    identity: identity,
    devices: devices,
    discovery: TvDiscovery(),
    share: ShareService(devices: devices, identity: identity),
  );
  runApp(TvRemoteApp(services: services));
}

class TvRemoteApp extends StatelessWidget {
  const TvRemoteApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final last = services.devices.lastUsed;
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'TV Remote',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // MaterialApp only builds a Navigator when a route source like this exists.
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const DevicesScreen()),
        // Like picking up the physical remote: open straight to the last TV.
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute<void>(builder: (_) => const DevicesScreen()),
          if (last != null) MaterialPageRoute<void>(builder: (_) => RemoteScreen(tv: last)),
        ],
      ),
    );
  }
}
