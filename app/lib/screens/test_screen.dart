import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../theme.dart';
import 'common.dart';

enum _Phase { ready, sending, success, failure }

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  _Phase _phase = _Phase.ready;
  String _error = '';

  Future<void> _send() async {
    setState(() => _phase = _Phase.sending);
    try {
      await AppScope.of(context).sendTestAlert();
      if (mounted) setState(() => _phase = _Phase.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failure;
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = AppScope.of(context);
    final contacts = state.config.contacts;
    final names = contacts.map((c) => c.name).join(', ');

    final String? blocker = !state.config.isComplete
        ? "Ajoutez d'abord votre nom et au moins un contact d'urgence."
        : !state.connected
        ? 'Approchez le bijou du téléphone pour lancer le test.'
        : null;

    final (
      IconData icon,
      Color color,
      String title,
      String body,
    ) = switch (_phase) {
      _Phase.ready => (
        Icons.notifications_active,
        brand,
        'Envoyer une alerte de test',
        blocker ??
            'Un message de test sera envoyé à : $names.\n\nPensez à les prévenir avant, pour ne pas les inquiéter.',
      ),
      _Phase.sending => (
        Icons.hourglass_top,
        brand,
        'Envoi en cours…',
        'Cela peut prendre une minute. Gardez le bijou près du téléphone.',
      ),
      _Phase.success => (
        Icons.check_circle,
        okGreen,
        'Test réussi',
        'Le message de test est parti. Demandez à vos contacts s\'ils l\'ont bien reçu.',
      ),
      _Phase.failure => (
        Icons.error,
        warnOrange,
        "Le test n'a pas fonctionné",
        _error,
      ),
    };

    return PopScope(
      canPop: _phase != _Phase.sending,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Tester l'alerte"),
          automaticallyImplyLeading: _phase != _Phase.sending,
        ),
        body: PageBody(
          actions: switch (_phase) {
            _Phase.ready => [
              FilledButton.icon(
                onPressed: blocker == null ? _send : null,
                icon: const Icon(Icons.send),
                label: const Text('Envoyer le test'),
              ),
            ],
            _Phase.sending => const [],
            _Phase.success => [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Retour à l'accueil"),
              ),
            ],
            _Phase.failure => [
              FilledButton.icon(
                onPressed: _send,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Retour à l'accueil"),
              ),
            ],
          },
          children: [
            const SizedBox(height: 32),
            if (_phase == _Phase.sending)
              const Center(
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(strokeWidth: 6),
                ),
              )
            else
              Icon(icon, size: 96, color: color),
            const SizedBox(height: 24),
            Text(
              title,
              style: text.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(body, style: text.bodyLarge, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
