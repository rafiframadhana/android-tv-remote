import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/shortcuts/catalog.dart';

/// User preferences: theme and the remote's app shortcuts.
class AppSettings extends ChangeNotifier {
  static const _themeKey = 'theme_mode';
  static const _shortcutsKey = 'shortcuts_v1';
  static const _overridesKey = 'shortcut_links_v1';
  static const _customKey = 'custom_shortcuts_v1';

  ThemeMode _themeMode = ThemeMode.system;
  List<String> _enabled = List.of(defaultShortcutIds);
  Map<String, String> _linkOverrides = {};
  List<CustomShortcut> _custom = [];

  ThemeMode get themeMode => _themeMode;

  /// Enabled shortcut ids, in the order shown on the remote.
  List<String> get enabledIds => List.unmodifiable(_enabled);

  List<CustomShortcut> get customShortcuts => List.unmodifiable(_custom);

  /// Every shortcut the user can choose from: the catalogue, then their own apps.
  List<TvShortcut> get allShortcuts => [
    for (final s in shortcutCatalog) _withOverride(s),
    for (final c in _custom) c.toShortcut(),
  ];

  /// The enabled shortcuts, resolved and in order.
  List<TvShortcut> get enabledShortcuts {
    final byId = {for (final s in allShortcuts) s.id: s};
    return [for (final id in _enabled) ?byId[id]];
  }

  bool isEnabled(String id) => _enabled.contains(id);
  bool hasLinkOverride(String id) => _linkOverrides.containsKey(id);

  TvShortcut _withOverride(TvShortcut s) {
    final o = _linkOverrides[s.id];
    return o == null ? s : s.withLink(o);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = switch (prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    try {
      final o = prefs.getString(_overridesKey);
      if (o != null) _linkOverrides = (jsonDecode(o) as Map).map((k, v) => MapEntry('$k', '$v'));
    } on Object {
      _linkOverrides = {};
    }
    try {
      final c = prefs.getString(_customKey);
      if (c != null) _custom = [for (final j in jsonDecode(c) as List) ?CustomShortcut.fromJson(j)];
    } on Object {
      _custom = [];
    }
    final saved = prefs.getStringList(_shortcutsKey);
    if (saved != null) {
      final known = {for (final s in allShortcuts) s.id};
      _enabled = [
        for (final id in saved)
          if (known.contains(id)) id,
      ];
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  /// Turning a shortcut on adds it at the end of the remote's grid.
  Future<void> setEnabled(String id, bool on) async {
    _enabled.remove(id);
    if (on) _enabled.add(id);
    await _saveEnabled();
  }

  /// Moves the enabled shortcut at [from] so it ends up at index [to].
  Future<void> moveEnabled(int from, int to) async {
    if (from < 0 || from >= _enabled.length) return;
    final id = _enabled.removeAt(from);
    _enabled.insert(to.clamp(0, _enabled.length), id);
    await _saveEnabled();
  }

  /// Sets the link for a catalogue shortcut; an empty [link] restores the default.
  Future<void> setLinkOverride(String id, String link) async {
    final trimmed = link.trim();
    if (trimmed.isEmpty) {
      _linkOverrides.remove(id);
    } else {
      _linkOverrides[id] = trimmed;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_overridesKey, jsonEncode(_linkOverrides));
  }

  /// Adds the user's own app (enabled straight away). Returns its id.
  Future<String> addCustom(String name, String link) async {
    var n = 1;
    while (_custom.any((c) => c.id == 'custom-$n')) {
      n++;
    }
    final c = CustomShortcut(id: 'custom-$n', name: name.trim(), link: link.trim());
    _custom.add(c);
    await _saveCustom();
    await setEnabled(c.id, true);
    return c.id;
  }

  Future<void> updateCustom(String id, {required String name, required String link}) async {
    _custom = [for (final c in _custom) c.id == id ? CustomShortcut(id: id, name: name.trim(), link: link.trim()) : c];
    await _saveCustom();
    notifyListeners();
  }

  Future<void> removeCustom(String id) async {
    _custom.removeWhere((c) => c.id == id);
    _enabled.remove(id);
    await _saveCustom();
    await _saveEnabled();
  }

  Future<void> _saveEnabled() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_shortcutsKey, _enabled);
  }

  Future<void> _saveCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customKey, jsonEncode([for (final c in _custom) c.toJson()]));
  }
}
