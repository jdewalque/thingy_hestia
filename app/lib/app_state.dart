import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jewel/ble_jewel.dart';
import 'jewel/demo_jewel.dart';
import 'jewel/jewel_link.dart';
import 'models.dart';

typedef LinkFactory = JewelLink Function({required bool demo});

JewelLink _defaultLinkFactory({required bool demo}) =>
    demo ? DemoJewel() : BleJewel();

/// État de l'application : bijou associé, réglages et synchronisation.
///
/// Les réglages sont toujours enregistrés sur le téléphone d'abord, puis
/// envoyés au bijou dès qu'il est à portée. L'utilisateur n'a donc jamais à
/// se soucier de la connexion pour modifier ses réglages.
class AppState extends ChangeNotifier {
  AppState(this._prefs, {this.linkFactory = _defaultLinkFactory}) {
    _jewelId = _prefs.getString(_kJewelId);
    _pendingSync = _prefs.getBool(_kPendingSync) ?? false;
    final saved = _prefs.getString(_kConfig);
    if (saved != null) {
      _config = JewelConfig.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    }
    final id = _jewelId;
    if (id != null) _attach(linkFactory(demo: id == demoJewelId), id);
  }

  static const _kJewelId = 'jewel_id';
  static const _kConfig = 'config';
  static const _kPendingSync = 'pending_sync';

  final SharedPreferences _prefs;
  final LinkFactory linkFactory;

  JewelLink? _link;
  Timer? _statusTimer;
  String? _jewelId;
  JewelConfig _config = const JewelConfig();
  bool _pendingSync = false;
  JewelStatus? _status;

  bool get isPaired => _jewelId != null;
  bool get isDemo => _jewelId == demoJewelId;
  bool get connected => _link?.connected.value ?? false;
  JewelConfig get config => _config;
  JewelStatus? get status => _status;

  /// Vrai tant que les derniers réglages n'ont pas été reçus par le bijou.
  bool get pendingSync => _pendingSync;

  /// Cherche un bijou à proximité et l'associe à ce téléphone.
  Future<void> pair({bool demo = false}) async {
    final link = linkFactory(demo: demo);
    try {
      final id = await link.findJewel();
      await _prefs.setString(_kJewelId, id);
      _jewelId = id;
      notifyListeners();
      await _attach(link, id);
    } catch (_) {
      if (_link != link) await link.dispose();
      rethrow;
    }
  }

  Future<void> unpair() async {
    _statusTimer?.cancel();
    _link?.connected.removeListener(_onConnectionChanged);
    await _link?.dispose();
    _link = null;
    _jewelId = null;
    _status = null;
    await _prefs.remove(_kJewelId);
    notifyListeners();
  }

  Future<void> _attach(JewelLink link, String id) async {
    _link = link;
    link.connected.addListener(_onConnectionChanged);
    try {
      await link.attach(id);
    } on JewelException {
      // La liaison retentera toute seule ; l'accueil indique « hors de portée ».
    }
  }

  void _onConnectionChanged() {
    notifyListeners();
    _statusTimer?.cancel();
    if (!connected) return;
    _statusTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshStatus(),
    );
    _onJewelReady();
  }

  Future<void> _onJewelReady() async {
    if (_pendingSync) {
      await _sync();
    } else if (_config.isEmpty) {
      // Téléphone neuf ou application réinstallée : on reprend les réglages
      // déjà présents dans le bijou.
      try {
        final response = await _link!.request('get_config');
        final remote = JewelConfig.fromJson(
          Map<String, dynamic>.from(response['config'] as Map),
        );
        if (_config.isEmpty && !remote.isEmpty) {
          _config = remote;
          await _prefs.setString(_kConfig, jsonEncode(remote.toJson()));
          notifyListeners();
        }
      } on JewelException {
        // Pas grave : l'utilisateur saisira ses réglages.
      }
    }
    await refreshStatus();
  }

  Future<void> updateConfig(JewelConfig config) async {
    _config = config;
    _pendingSync = true;
    notifyListeners();
    await _prefs.setString(_kConfig, jsonEncode(config.toJson()));
    await _prefs.setBool(_kPendingSync, true);
    // L'envoi au bijou se fait en arrière-plan : l'écran n'attend pas le
    // Bluetooth pour confirmer l'enregistrement.
    unawaited(_sync());
  }

  Future<void> _sync() async {
    final link = _link;
    if (link == null || !connected) return;
    final sent = _config;
    try {
      await link.request('set_config', args: {'config': sent.toJson()});
    } on JewelException {
      return; // Nouvel essai à la prochaine connexion.
    }
    // Les réglages ont pu changer pendant l'envoi : dans ce cas l'envoi
    // suivant est déjà en route.
    if (!identical(sent, _config)) return;
    _pendingSync = false;
    await _prefs.setBool(_kPendingSync, false);
    notifyListeners();
  }

  Future<void> refreshStatus() async {
    final link = _link;
    if (link == null || !connected) return;
    try {
      final response = await link.request('get_status');
      _status = JewelStatus.fromJson(
        Map<String, dynamic>.from(response['status'] as Map),
      );
      notifyListeners();
    } on JewelException {
      // On garde le dernier état connu.
    }
  }

  /// Demande au bijou d'envoyer une alerte de test, comme si le bouton avait
  /// été pressé. Lève une [JewelException] en cas d'échec.
  Future<void> sendTestAlert() async {
    final link = _link;
    if (link == null || !connected) {
      throw const JewelException(JewelError.notConnected);
    }
    if (_pendingSync) await _sync();
    if (_pendingSync) throw const JewelException(JewelError.notConnected);
    await link.request('test_alert', timeout: const Duration(seconds: 90));
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _link?.connected.removeListener(_onConnectionChanged);
    _link?.dispose();
    super.dispose();
  }
}

/// Donne accès à l'[AppState] depuis les écrans, qui se reconstruisent à
/// chaque changement.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
