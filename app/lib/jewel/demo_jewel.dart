import 'package:flutter/foundation.dart';

import 'jewel_link.dart';

const String demoJewelId = 'demo';

/// Bijou simulé : répond comme le vrai, sans Bluetooth.
class DemoJewel implements JewelLink {
  DemoJewel({this.delay = const Duration(milliseconds: 900)});

  final Duration delay;
  final ValueNotifier<bool> _connected = ValueNotifier(false);
  Map<String, dynamic> _config = {'name': '', 'message': '', 'contacts': []};

  @override
  ValueListenable<bool> get connected => _connected;

  @override
  Future<String> findJewel() async {
    await Future<void>.delayed(delay * 2);
    return demoJewelId;
  }

  @override
  Future<void> attach(String id) async {
    await Future<void>.delayed(delay);
    _connected.value = true;
  }

  @override
  Future<Map<String, dynamic>> request(
    String cmd, {
    Map<String, dynamic>? args,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!_connected.value) throw const JewelException(JewelError.notConnected);
    await Future<void>.delayed(cmd == 'test_alert' ? delay * 3 : delay);
    switch (cmd) {
      case 'get_status':
        return {
          'ok': true,
          'status': {'battery': 82, 'lte': 'connected'},
        };
      case 'get_config':
        return {'ok': true, 'config': _config};
      case 'set_config':
        _config = Map<String, dynamic>.from(args!['config'] as Map);
        return {'ok': true};
      case 'test_alert':
        return {'ok': true};
    }
    throw JewelException(JewelError.rejected, 'unknown_cmd');
  }

  @override
  Future<void> dispose() async => _connected.value = false;
}
