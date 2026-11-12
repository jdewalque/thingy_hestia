import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hestia/app_state.dart';
import 'package:hestia/jewel/demo_jewel.dart';
import 'package:hestia/jewel/jewel_link.dart';
import 'package:hestia/jewel/protocol.dart';
import 'package:hestia/main.dart';
import 'package:hestia/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _delay = Duration(milliseconds: 10);

/// Bijou de démonstration dont on peut couper la connexion et lire le contenu.
class _FakeJewel extends DemoJewel {
  _FakeJewel() : super(delay: _delay);

  final ValueNotifier<bool> inRange = ValueNotifier(true);
  final List<String> commands = [];
  Map<String, dynamic>? storedConfig;

  @override
  ValueListenable<bool> get connected => inRange.value ? super.connected : inRange;

  @override
  Future<Map<String, dynamic>> request(
    String cmd, {
    Map<String, dynamic>? args,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!inRange.value) throw const JewelException(JewelError.notConnected);
    commands.add(cmd);
    if (cmd == 'set_config') storedConfig = args!['config'] as Map<String, dynamic>;
    return super.request(cmd, args: args, timeout: timeout);
  }
}

Future<AppState> _state(_FakeJewel jewel, [Map<String, Object> saved = const {}]) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();
  return AppState(prefs, linkFactory: ({required demo}) => jewel);
}

void main() {
  group('numéros de téléphone', () {
    test('nettoyage et format international', () {
      expect(normalizePhone('0470 12 34 56', countryCode: 'BE'), '+32470123456');
      expect(normalizePhone('06.12.34.56.78', countryCode: 'FR'), '+33612345678');
      expect(normalizePhone('0032 470 12 34 56'), '+32470123456');
      expect(normalizePhone('+33 6 12 34 56 78', countryCode: 'BE'), '+33612345678');
      expect(normalizePhone('0470123456'), '0470123456');
    });

    test('affichage par groupes', () {
      expect(formatPhone('+32470123456'), '+32 470 12 34 56');
      expect(formatPhone('+33612345678'), '+33 612 34 56 78');
      expect(formatPhone('0470123456'), '04 70 12 34 56');
    });

    test('numéros invalides refusés', () {
      expect(normalizePhone('12345'), isNull);
      expect(normalizePhone('abc'), isNull);
      expect(normalizePhone(''), isNull);
    });
  });

  group('protocole', () {
    test('une requête est une ligne JSON', () {
      final bytes = encodeRequest(7, 'get_status', null);
      expect(String.fromCharCodes(bytes), '{"id":7,"cmd":"get_status"}\n');
    });

    test('les réponses fragmentées sont reconstituées', () {
      final decoder = LineDecoder();
      final bytes = '{"id":1,"ok":true}\n{"id":2,"ok":false,"error":"no_network"}\n'.codeUnits;
      final messages = [
        ...decoder.add(bytes.sublist(0, 5)),
        ...decoder.add(bytes.sublist(5, 30)),
        ...decoder.add(bytes.sublist(30)),
      ];
      expect(messages, hasLength(2));
      expect(checkResponse(messages[0])['id'], 1);
      expect(
        () => checkResponse(messages[1]),
        throwsA(isA<JewelException>().having((e) => e.error, 'error', JewelError.noNetwork)),
      );
    });
  });

  group('synchronisation', () {
    const config = JewelConfig(
      wearerName: 'Marie',
      message: 'Aidez-moi',
      contacts: [EmergencyContact(name: 'Paul', phone: '+32470123456')],
    );

    test('les réglages modifiés hors de portée partent à la reconnexion', () async {
      final jewel = _FakeJewel();
      final state = await _state(jewel);
      await state.pair(demo: true);
      await Future<void>.delayed(_delay * 5);

      jewel.inRange.value = false;
      await state.updateConfig(config);
      expect(state.pendingSync, isTrue);
      expect(jewel.storedConfig, isNull);
      await expectLater(state.sendTestAlert(), throwsA(isA<JewelException>()));

      jewel.inRange.value = true;
      await state.updateConfig(config.copyWith(message: 'Venez vite'));
      await Future<void>.delayed(_delay * 5);
      expect(state.pendingSync, isFalse);
      expect(jewel.storedConfig!['message'], 'Venez vite');
      expect(jewel.storedConfig!['contacts'], [
        {'name': 'Paul', 'phone': '+32470123456'},
      ]);

      await state.sendTestAlert();
      expect(jewel.commands.last, 'test_alert');
      state.dispose();
    });

    test('un envoi en attente est repris au redémarrage', () async {
      final jewel = _FakeJewel();
      final state = await _state(jewel, {
        'jewel_id': demoJewelId,
        'pending_sync': true,
        'config': '{"name":"Marie","message":"Aidez-moi","contacts":[]}',
      });
      await Future<void>.delayed(_delay * 10);
      expect(jewel.storedConfig!['name'], 'Marie');
      expect(state.pendingSync, isFalse);
      expect(state.status!.battery, 82);
      state.dispose();
    });
  });

  testWidgets('parcours complet en mode démonstration', (tester) async {
    // Taille d'un téléphone courant.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final jewel = _FakeJewel();
    final state = await tester.runAsync(() => _state(jewel));
    await tester.pumpWidget(HestiaApp(state: state!));

    expect(find.text('Rechercher mon bijou'), findsOneWidget);
    await tester.tap(find.text('Essayer sans bijou'));
    await tester.pumpAndSettle();

    expect(find.text('Bijou connecté'), findsOneWidget);
    expect(find.textContaining('Ajoutez au moins un contact'), findsOneWidget);

    // Ajout d'un contact saisi à la main.
    await tester.tap(find.text("Mes contacts d'urgence"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saisir un numéro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Indiquez le nom de la personne.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Paul Martin');
    await tester.enterText(find.byType(TextFormField).at(1), '+32 470 12 34 56');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Paul Martin'), findsOneWidget);
    expect(find.text('+32 470 12 34 56'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 contact'), findsOneWidget);

    // Nom : le message par défaut est proposé automatiquement.
    await tester.tap(find.text('Mon nom et mon message'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Marie Dupont');
    await tester.pump();
    expect(find.textContaining("Marie Dupont a appuyé sur son bouton d'urgence"), findsWidgets);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Vos réglages sont enregistrés.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Marie Dupont'), findsOneWidget);
    expect(find.textContaining('Indiquez votre nom'), findsNothing);
    expect(find.textContaining('Ajoutez au moins un contact'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(jewel.storedConfig!['name'], 'Marie Dupont');

    // Alerte de test.
    await tester.tap(find.text("Tester l'alerte"));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paul Martin'), findsOneWidget);
    await tester.tap(find.text('Envoyer le test'));
    await tester.pumpAndSettle();
    expect(find.text('Test réussi'), findsOneWidget);
    expect(jewel.commands, contains('test_alert'));

    state.dispose();
  });
}
