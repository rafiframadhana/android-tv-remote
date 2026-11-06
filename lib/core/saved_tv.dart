/// A paired TV as stored on this phone. Plain Dart (no Flutter), so tools can use it too.
class SavedTv {
  const SavedTv({required this.host, required this.name, this.pins = const [], this.remoteVerified = false});

  final String host;
  final String name;

  /// SHA-256 fingerprints (hex) of the TV's TLS certificate(s), recorded at pairing.
  /// The phone only talks to a TV that presents one of these — see core/pinning.dart.
  final List<String> pins;

  /// Whether a remote-port connection has been checked against [pins] since pairing.
  final bool remoteVerified;

  SavedTv copyWith({String? host, String? name, List<String>? pins, bool? remoteVerified}) => SavedTv(
    host: host ?? this.host,
    name: name ?? this.name,
    pins: pins ?? this.pins,
    remoteVerified: remoteVerified ?? this.remoteVerified,
  );

  Map<String, Object> toJson() => {'host': host, 'name': name, 'pins': pins, 'remoteVerified': remoteVerified};

  static SavedTv fromJson(Map<String, Object?> j) => SavedTv(
    host: j['host']! as String,
    name: j['name']! as String,
    pins: [for (final p in (j['pins'] as List?) ?? const []) p as String],
    remoteVerified: (j['remoteVerified'] as bool?) ?? false,
  );
}
