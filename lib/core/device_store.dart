import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'saved_tv.dart';

export 'saved_tv.dart';

/// Paired TVs, most recently used first. A TV is identified by its address
/// (names aren't unique: many TVs are simply called "Android TV").
class DeviceStore extends ChangeNotifier {
  static const _key = 'paired_tvs_v1';

  List<SavedTv> _tvs = const [];
  List<SavedTv> get tvs => _tvs;
  SavedTv? get lastUsed => _tvs.firstOrNull;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      _tvs = [for (final j in jsonDecode(raw) as List) SavedTv.fromJson((j as Map).cast())];
    } on Object {
      _tvs = const [];
    }
    notifyListeners();
  }

  SavedTv? byHost(String host) => _tvs.where((t) => t.host == host).firstOrNull;

  /// Adds or moves [tv] to the front (most recently used), replacing the entry with the same host.
  Future<void> touch(SavedTv tv) => _save([tv, ..._tvs.where((t) => t.host != tv.host)]);

  /// Replaces the entry stored under [oldHost] (e.g. the TV got a new IP, or its pins changed).
  /// Any other entry already at the new host is dropped (one entry per address).
  Future<void> replace(String oldHost, SavedTv tv) => _save([
    for (final t in _tvs)
      if (t.host == oldHost) tv else if (t.host != tv.host) t,
  ]);

  Future<void> forget(SavedTv tv) => _save(_tvs.where((t) => t.host != tv.host).toList());

  Future<void> _save(List<SavedTv> tvs) async {
    _tvs = List.unmodifiable(tvs);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final t in _tvs) t.toJson()]));
  }
}
