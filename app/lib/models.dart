/// Données échangées entre l'application et le bijou.
library;

const int maxContacts = 5;
const int maxMessageLength = 120;

class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone});

  final String name;

  /// Numéro sans séparateurs, de préférence au format international (+32…).
  final String phone;

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        name: (json['name'] ?? '') as String,
        phone: (json['phone'] ?? '') as String,
      );
}

class JewelConfig {
  const JewelConfig({
    this.wearerName = '',
    this.message = '',
    this.contacts = const [],
  });

  final String wearerName;
  final String message;
  final List<EmergencyContact> contacts;

  bool get isEmpty => wearerName.isEmpty && message.isEmpty && contacts.isEmpty;

  /// Le bijou ne peut alerter personne tant qu'il manque un nom ou un contact.
  bool get isComplete => wearerName.isNotEmpty && contacts.isNotEmpty;

  JewelConfig copyWith({
    String? wearerName,
    String? message,
    List<EmergencyContact>? contacts,
  }) => JewelConfig(
    wearerName: wearerName ?? this.wearerName,
    message: message ?? this.message,
    contacts: contacts ?? this.contacts,
  );

  Map<String, dynamic> toJson() => {
    'name': wearerName,
    'message': message,
    'contacts': [for (final c in contacts) c.toJson()],
  };

  factory JewelConfig.fromJson(Map<String, dynamic> json) => JewelConfig(
    wearerName: (json['name'] ?? '') as String,
    message: (json['message'] ?? '') as String,
    contacts: [
      for (final c in (json['contacts'] as List? ?? const []))
        EmergencyContact.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
  );
}

enum LteState { connected, searching, off }

class JewelStatus {
  const JewelStatus({this.battery, this.lte = LteState.off});

  /// Pourcentage de batterie, ou null si inconnu.
  final int? battery;
  final LteState lte;

  factory JewelStatus.fromJson(Map<String, dynamic> json) => JewelStatus(
    battery: (json['battery'] as num?)?.toInt(),
    lte: switch (json['lte']) {
      'connected' => LteState.connected,
      'searching' => LteState.searching,
      _ => LteState.off,
    },
  );
}

String defaultMessage(String name) =>
    name.isEmpty ? '' : "$name a appuyé sur son bouton d'urgence et a besoin d'aide.";

const _dialCodes = {'FR': '33', 'BE': '32', 'CH': '41', 'LU': '352'};

/// Nettoie un numéro saisi ou venant du répertoire. Retourne null s'il est
/// invalide. Les numéros nationaux (0…) sont convertis au format international
/// quand le pays du téléphone est connu, car le serveur d'envoi de SMS en a
/// besoin.
String? normalizePhone(String raw, {String? countryCode}) {
  var s = raw.replaceAll(RegExp(r'[\s.\-()/]'), '');
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  if (!RegExp(r'^\+?\d{8,15}$').hasMatch(s)) return null;
  final dial = _dialCodes[countryCode?.toUpperCase()];
  if (s.startsWith('0') && dial != null) s = '+$dial${s.substring(1)}';
  return s;
}

/// Affiche un numéro par groupes de chiffres, plus facile à relire :
/// « +32 470 12 34 56 », « 04 70 12 34 56 ».
String formatPhone(String phone) {
  var prefix = '';
  var digits = phone;
  if (phone.startsWith('+')) {
    final dial = _dialCodes.values.firstWhere(
      (d) => phone.startsWith('+$d'),
      orElse: () => '',
    );
    prefix = '+$dial${dial.isEmpty ? '' : ' '}';
    digits = phone.substring(1 + dial.length);
  }
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 2) {
    groups.insert(0, digits.substring(end < 2 ? 0 : end - 2, end));
  }
  if (groups.length > 1 && groups.first.length == 1) {
    final first = groups.removeAt(0);
    groups[0] = first + groups[0];
  }
  return prefix + groups.join(' ');
}
