import 'package:flutter/widgets.dart';
import 'package:simple_icons/simple_icons.dart';

/// How a shortcut's icon is drawn.
sealed class ShortcutIcon {
  const ShortcutIcon();
}

/// A brand glyph from Simple Icons (CC0 icon set), drawn white on the brand colour.
class GlyphIcon extends ShortcutIcon {
  const GlyphIcon(this.data);
  final IconData data;
}

/// A bundled image that already is a complete app tile (e.g. BitTV's own icon).
class AssetIcon extends ShortcutIcon {
  const AssetIcon(this.path);
  final String path;
}

/// Initials on the brand colour, for apps without a usable logo.
class BadgeIcon extends ShortcutIcon {
  const BadgeIcon(this.letters);
  final String letters;
}

/// An app the remote can open on the TV.
///
/// [link] is sent with remote_app_link_launch_request; the TV opens it with
/// `Intent(ACTION_VIEW, Uri.parse(link))`, so it must be a URI the app's Android TV build handles.
/// An empty [link] means the app has no known link: it is opened through its Play Store page
/// ([storeFallback]) or, for [template] entries, isn't configured yet.
/// Links come from the Home Assistant androidtv_remote docs and community deep-link guide.
class TvShortcut {
  const TvShortcut({
    required this.id,
    required this.name,
    required this.link,
    required this.package,
    required this.icon,
    required this.color,
    this.verified = false,
    this.storeFallback = false,
    this.template = false,
    this.extraPackages = const [],
  });

  /// Stable key used in settings.
  final String id;
  final String name;
  final String link;

  /// Android TV package; the TV reports it when the app is in front, which confirms a launch.
  final String package;

  /// Other packages that count as "this app opened" (alternate TV builds).
  final List<String> extraPackages;
  final ShortcutIcon icon;
  final Color color;

  /// The link was confirmed on a real TV.
  final bool verified;

  /// No known link: open the app's Play Store page and press "Open".
  final bool storeFallback;

  /// Placeholder until the link is found on a real TV; the user can set it in Settings.
  final bool template;

  bool matchesPackage(String pkg) => pkg.isNotEmpty && (pkg == package || extraPackages.contains(pkg));

  TvShortcut withLink(String newLink) => TvShortcut(
    id: id,
    name: name,
    link: newLink,
    package: package,
    icon: icon,
    color: color,
    verified: verified,
    storeFallback: storeFallback && newLink.isEmpty,
    template: template && newLink.isEmpty,
    extraPackages: extraPackages,
  );
}

/// Shortcuts on the remote the first time the app runs.
const defaultShortcutIds = ['youtube', 'netflix', 'primevideo', 'disneyplus'];

/// Order here is the order in Settings.
const shortcutCatalog = <TvShortcut>[
  TvShortcut(
    id: 'youtube',
    name: 'YouTube',
    link: 'https://www.youtube.com',
    package: 'com.google.android.youtube.tv',
    icon: GlyphIcon(SimpleIcons.youtube),
    color: Color(0xFFFF0000),
    verified: true,
  ),
  TvShortcut(
    id: 'netflix',
    name: 'Netflix',
    link: 'netflix://',
    package: 'com.netflix.ninja',
    icon: GlyphIcon(SimpleIcons.netflix),
    color: Color(0xFFE50914),
    verified: true,
  ),
  TvShortcut(
    id: 'primevideo',
    name: 'Prime Video',
    link: 'https://app.primevideo.com',
    package: 'com.amazon.amazonvideo.livingroom',
    icon: BadgeIcon('PV'),
    color: Color(0xFF1A98FF),
    verified: true,
  ),
  TvShortcut(
    id: 'disneyplus',
    name: 'Disney+',
    link: 'https://www.disneyplus.com',
    package: 'com.disney.disneyplus',
    icon: BadgeIcon('D+'),
    color: Color(0xFF113CCF),
  ),
  TvShortcut(
    id: 'hotstar',
    name: 'Disney+ Hotstar',
    link: 'https://www.apps.disneyplus.com',
    package: 'in.startv.hotstar.dplus.tv',
    icon: BadgeIcon('D+'),
    color: Color(0xFF0C1C4D),
  ),
  TvShortcut(
    id: 'playstore',
    name: 'Play Store',
    link: 'market://search?q=',
    package: 'com.android.vending',
    icon: GlyphIcon(SimpleIcons.googleplay),
    color: Color(0xFF01875F),
    verified: true,
  ),
  TvShortcut(
    id: 'bittv',
    name: 'BitTV',
    // BitTVActivity registers VIEW for the schemes tv:// and channel:// (read from the app on a
    // Panasonic Android TV; no other app there claims tv://).
    link: 'tv://',
    package: 'com.live_streaming_tv.online_tv',
    icon: AssetIcon('assets/shortcuts/bittv.png'),
    color: Color(0xFF227B93),
    verified: true,
  ),
  TvShortcut(
    id: 'ytmusic',
    name: 'YouTube Music',
    link: 'https://music.youtube.com/',
    package: 'com.google.android.youtube.tvmusic',
    // On some TVs the YouTube Music app hands over to YouTube (its own launcher icon does the
    // same), so YouTube in front counts as opened.
    extraPackages: ['com.google.android.youtube.tv'],
    icon: GlyphIcon(SimpleIcons.youtubemusic),
    color: Color(0xFFFF0000),
    verified: true,
  ),
  TvShortcut(
    id: 'ytkids',
    name: 'YouTube Kids',
    link: 'https://kids.youtube.com/',
    package: 'com.google.android.youtube.tvkids',
    icon: GlyphIcon(SimpleIcons.youtubekids),
    color: Color(0xFFFF0000),
  ),
  TvShortcut(
    id: 'spotify',
    name: 'Spotify',
    link: 'spotify://',
    package: 'com.spotify.tv.android',
    icon: GlyphIcon(SimpleIcons.spotify),
    color: Color(0xFF1DB954),
  ),
  TvShortcut(
    id: 'twitch',
    name: 'Twitch',
    link: 'twitch://home',
    package: 'tv.twitch.android.app',
    icon: GlyphIcon(SimpleIcons.twitch),
    color: Color(0xFF9146FF),
  ),
  TvShortcut(
    id: 'plex',
    name: 'Plex',
    link: 'plex://',
    package: 'com.plexapp.android',
    icon: GlyphIcon(SimpleIcons.plex),
    color: Color(0xFF282A2D),
  ),
  TvShortcut(
    id: 'vlc',
    name: 'VLC',
    link: 'vlc://',
    package: 'org.videolan.vlc',
    icon: GlyphIcon(SimpleIcons.vlcmediaplayer),
    color: Color(0xFFFF8800),
  ),
  TvShortcut(
    id: 'max',
    name: 'HBO Max',
    link: 'https://play.hbomax.com',
    package: 'com.wbd.stream',
    icon: GlyphIcon(SimpleIcons.hbomax),
    color: Color(0xFF002BE7),
  ),
  TvShortcut(
    id: 'appletv',
    name: 'Apple TV',
    link: 'https://tv.apple.com',
    package: 'com.apple.atve.androidtv.appletv',
    icon: GlyphIcon(SimpleIcons.appletv),
    color: Color(0xFF111111),
  ),
  TvShortcut(
    id: 'paramount',
    name: 'Paramount+',
    link: 'https://www.paramountplus.com/',
    package: 'com.cbs.ott',
    icon: GlyphIcon(SimpleIcons.paramountplus),
    color: Color(0xFF0064FF),
  ),
  TvShortcut(
    id: 'peacock',
    name: 'Peacock',
    link: 'https://www.peacocktv.com/deeplink',
    package: 'com.peacocktv.peacockandroid',
    icon: BadgeIcon('P'),
    color: Color(0xFF111111),
  ),
  TvShortcut(
    id: 'crunchyroll',
    name: 'Crunchyroll',
    link: 'crunchyroll://',
    package: 'com.crunchyroll.crunchyroid',
    icon: GlyphIcon(SimpleIcons.crunchyroll),
    color: Color(0xFFFF5E00),
  ),
  TvShortcut(
    id: 'tubi',
    name: 'Tubi',
    link: 'https://tubitv.com/',
    package: 'com.tubitv',
    icon: GlyphIcon(SimpleIcons.tubi),
    color: Color(0xFF7408FF),
  ),
  TvShortcut(
    id: 'plutotv',
    name: 'Pluto TV',
    link: 'https://pluto.tv/en/live-tv',
    package: 'tv.pluto.android',
    icon: BadgeIcon('PL'),
    color: Color(0xFF2C2C2C),
  ),
  TvShortcut(
    id: 'deezer',
    name: 'Deezer',
    link: 'deezer://www.deezer.com',
    package: 'deezer.android.tv',
    icon: GlyphIcon(SimpleIcons.deezer),
    color: Color(0xFFA238FF),
  ),
  TvShortcut(
    id: 'emby',
    name: 'Emby',
    link: 'embyatv://tv.emby.embyatv/startapp',
    package: 'tv.emby.embyatv',
    icon: GlyphIcon(SimpleIcons.emby),
    color: Color(0xFF52B54B),
  ),
  TvShortcut(
    id: 'smarttube',
    name: 'SmartTube',
    link: 'vnd.youtube.launch://www.youtube.com',
    package: 'com.teamsmart.videomanager.tv',
    extraPackages: ['com.liskovsoft.smarttubetv.beta', 'org.smartteam.smarttube.tv'],
    icon: BadgeIcon('ST'),
    color: Color(0xFFE53935),
  ),
  TvShortcut(
    id: 'googletv',
    name: 'Google TV',
    link: 'https://play.google.com/movies',
    package: 'com.google.android.videos',
    icon: BadgeIcon('G'),
    color: Color(0xFF4285F4),
    verified: true,
  ),
  TvShortcut(
    id: 'stremio',
    name: 'Stremio',
    link: 'stremio:///board',
    package: 'com.stremio.one',
    icon: GlyphIcon(SimpleIcons.stremio),
    color: Color(0xFF685CEE),
    verified: true,
  ),
  TvShortcut(
    id: 'vidio',
    name: 'Vidio',
    link: 'vidio://',
    package: 'com.vidio.android.tv',
    icon: BadgeIcon('V'),
    color: Color(0xFFEE2B5A),
  ),
  TvShortcut(
    id: 'wetv',
    name: 'WeTV',
    link: 'https://wetv.vip',
    package: 'com.tencent.qqlivei18n',
    icon: BadgeIcon('We'),
    color: Color(0xFFFF6F00),
  ),
  TvShortcut(
    id: 'iqiyi',
    name: 'iQIYI',
    link: 'https://www.iq.com',
    package: 'com.iqiyi.i18n.tv',
    icon: BadgeIcon('iQ'),
    color: Color(0xFF00BE06),
  ),
  TvShortcut(
    id: 'viu',
    name: 'Viu',
    link: 'https://www.viu.com',
    package: 'com.viu.tv',
    icon: BadgeIcon('Viu'),
    color: Color(0xFFF6B900),
  ),
  TvShortcut(
    id: 'catchplay',
    name: 'CATCHPLAY+',
    link: 'https://www.catchplay.com',
    package: 'com.catchplay.asiaplay.common.tv',
    icon: BadgeIcon('C+'),
    color: Color(0xFF1B1B1B),
  ),
  TvShortcut(
    id: 'rctiplus',
    name: 'RCTI+',
    link: 'https://www.rctiplus.com',
    package: 'com.rctiplus.atv',
    icon: BadgeIcon('R+'),
    color: Color(0xFF0A3D91),
  ),
  TvShortcut(
    id: 'kodi',
    name: 'Kodi',
    link: '',
    package: 'org.xbmc.kodi',
    icon: GlyphIcon(SimpleIcons.kodi),
    color: Color(0xFF17B2E7),
    storeFallback: true,
  ),
  TvShortcut(
    id: 'jellyfin',
    name: 'Jellyfin',
    link: '',
    package: 'org.jellyfin.androidtv',
    icon: GlyphIcon(SimpleIcons.jellyfin),
    color: Color(0xFF00A4DC),
    storeFallback: true,
  ),
  TvShortcut(
    id: 'hulu',
    name: 'Hulu',
    link: '',
    package: 'com.hulu.livingroomplus',
    icon: BadgeIcon('H'),
    color: Color(0xFF1CE783),
    storeFallback: true,
  ),
  TvShortcut(
    id: 'tidal',
    name: 'TIDAL',
    link: '',
    package: 'com.aspiro.tidal',
    icon: GlyphIcon(SimpleIcons.tidal),
    color: Color(0xFF111111),
    storeFallback: true,
  ),
];

/// A shortcut the user added themselves (name + link).
class CustomShortcut {
  const CustomShortcut({required this.id, required this.name, required this.link});
  final String id;
  final String name;
  final String link;

  Map<String, String> toJson() => {'id': id, 'name': name, 'link': link};

  static CustomShortcut? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], link = j['link'];
    if (id is! String || name is! String || link is! String) return null;
    return CustomShortcut(id: id, name: name, link: link);
  }

  TvShortcut toShortcut() => TvShortcut(
    id: id,
    name: name,
    link: link,
    package: '',
    icon: BadgeIcon(initials(name)),
    color: const Color(0xFF546E7A),
  );
}

/// One or two letters for a badge: "Living Room" → "LR", "kodi" → "K".
String initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.characters.first.toUpperCase();
  return (words[0].characters.first + words[1].characters.first).toUpperCase();
}

/// Friendly name for a foreground package, for the "now on screen" line.
String appNameFor(String packageName) {
  for (final s in shortcutCatalog) {
    if (s.matchesPackage(packageName)) return s.name;
  }
  const known = {
    'com.google.android.tvlauncher': 'Home',
    'com.google.android.apps.tv.launcherx': 'Home',
    'com.google.android.leanbacklauncher': 'Home',
    'com.android.tv.settings': 'Settings',
    'com.android.tv': 'Live TV',
    'com.google.android.katniss': 'Google Assistant',
  };
  if (known[packageName] case final name?) return name;
  final last = packageName.split('.').last;
  return last.isEmpty ? packageName : last[0].toUpperCase() + last.substring(1);
}
