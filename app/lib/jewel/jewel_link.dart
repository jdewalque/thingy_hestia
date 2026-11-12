import 'package:flutter/foundation.dart';

enum JewelError {
  bluetoothOff,
  permission,
  notFound,
  notConnected,
  timeout,
  noNetwork,
  noContact,
  smsFailed,
  busy,
  rejected,
}

class JewelException implements Exception {
  const JewelException(this.error, [this.detail]);
  final JewelError error;
  final String? detail;

  @override
  String toString() =>
      'JewelException(${error.name}${detail == null ? '' : ', $detail'})';
}

/// Liaison avec un bijou. Deux implémentations : Bluetooth (réelle) et
/// démonstration (simulée, pour essayer l'application sans bijou).
abstract class JewelLink {
  /// Vrai quand le bijou est à portée et prêt à recevoir des commandes.
  ValueListenable<bool> get connected;

  /// Cherche un bijou à proximité et retourne son identifiant.
  Future<String> findJewel();

  /// Maintient la connexion avec le bijou [id], y compris après une perte de
  /// portée.
  Future<void> attach(String id);

  /// Envoie une commande et attend la réponse du bijou.
  Future<Map<String, dynamic>> request(
    String cmd, {
    Map<String, dynamic>? args,
    Duration timeout = const Duration(seconds: 10),
  });

  Future<void> dispose();
}
