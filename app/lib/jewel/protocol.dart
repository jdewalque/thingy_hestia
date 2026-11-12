/// Protocole Bluetooth entre l'application et le bijou.
/// Décrit en détail dans docs/protocole-ble.md : toute modification ici doit y
/// être reportée, le firmware s'appuie dessus.
library;

import 'dart:convert';

import 'jewel_link.dart';

/// Service « Nordic UART » : c'est celui qu'expose le nRF5340 du Thingy:91 X,
/// qui relaie ensuite les messages au nRF9151 par liaison série.
const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

/// Application → bijou (write).
const String rxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

/// Bijou → application (notify).
const String txUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

const int _newline = 0x0A;

List<int> encodeRequest(int id, String cmd, Map<String, dynamic>? args) =>
    utf8.encode('${jsonEncode({'id': id, 'cmd': cmd, ...?args})}\n');

/// Reconstitue les messages (une ligne JSON chacun) à partir des fragments
/// reçus par notification.
class LineDecoder {
  final List<int> _buffer = [];

  List<Map<String, dynamic>> add(List<int> chunk) {
    final messages = <Map<String, dynamic>>[];
    for (final byte in chunk) {
      if (byte != _newline) {
        _buffer.add(byte);
        continue;
      }
      try {
        final decoded = jsonDecode(utf8.decode(_buffer));
        if (decoded is Map) messages.add(Map<String, dynamic>.from(decoded));
      } on FormatException {
        // Ligne illisible : ignorée, la requête correspondante expirera.
      }
      _buffer.clear();
    }
    return messages;
  }

  void reset() => _buffer.clear();
}

/// Retourne la réponse si elle est positive, lève une [JewelException] sinon.
Map<String, dynamic> checkResponse(Map<String, dynamic> response) {
  if (response['ok'] == true) return response;
  final code = response['error'] as String?;
  throw JewelException(switch (code) {
    'no_network' => JewelError.noNetwork,
    'no_contact' => JewelError.noContact,
    'send_failed' => JewelError.sendFailed,
    'busy' => JewelError.busy,
    _ => JewelError.rejected,
  }, code);
}
