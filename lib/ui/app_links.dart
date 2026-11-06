/// App shortcut keys, launched by deep link (package-name launch is broken by a
/// Google Play change, see docs/research). Links from Home Assistant's table.
class AppLink {
  const AppLink(this.name, this.link, this.packageName);
  final String name;
  final String link;

  /// Foreground package, used to show the current app by name.
  final String packageName;
}

const appLinks = [
  AppLink('YouTube', 'https://www.youtube.com', 'com.google.android.youtube.tv'),
  AppLink('Netflix', 'netflix://', 'com.netflix.ninja'),
  AppLink('Prime Video', 'https://app.primevideo.com', 'com.amazon.amazonvideo.livingroom'),
  AppLink('Disney+', 'https://www.disneyplus.com', 'com.disney.disneyplus'),
];

/// Friendly name for a foreground package, falling back to the last segment.
String appNameFor(String packageName) {
  for (final a in appLinks) {
    if (a.packageName == packageName) return a.name;
  }
  const known = {
    'com.google.android.tvlauncher': 'Home',
    'com.google.android.apps.tv.launcherx': 'Home',
    'com.google.android.leanbacklauncher': 'Home',
    'com.android.tv.settings': 'Settings',
    'com.google.android.katniss': 'Google Assistant',
    'com.google.android.youtube.tvmusic': 'YouTube Music',
    'com.spotify.tv.android': 'Spotify',
    'org.xbmc.kodi': 'Kodi',
    'com.plexapp.android': 'Plex',
  };
  if (known[packageName] case final name?) return name;
  final last = packageName.split('.').last;
  return last.isEmpty ? packageName : last[0].toUpperCase() + last.substring(1);
}
