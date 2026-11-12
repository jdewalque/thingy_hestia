import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Premier lancement : relier le bijou au téléphone.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _searching = false;
  String? _error;

  Future<void> _pair({bool demo = false}) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      await AppScope.of(context).pair(demo: demo);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: PageBody(
        actions: _searching
            ? const []
            : [
                FilledButton.icon(
                  onPressed: _pair,
                  icon: const Icon(Icons.search),
                  label: Text(_error == null ? 'Rechercher mon bijou' : 'Réessayer'),
                ),
                TextButton(
                  onPressed: () => _pair(demo: true),
                  child: const Text('Essayer sans bijou'),
                ),
              ],
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.favorite, size: 88, color: brand),
          const SizedBox(height: 20),
          Text('Bienvenue', style: text.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Nous allons relier votre bijou à ce téléphone.',
            style: text.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_searching) ...[
            const Center(
              child: SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(strokeWidth: 6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Recherche du bijou…\nGardez-le près du téléphone.',
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
          ] else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 36, color: warnOrange),
                    const SizedBox(width: 16),
                    Expanded(child: Text(_error!, style: text.bodyLarge)),
                  ],
                ),
              ),
            )
          else ...[
            const _Step(number: '1', text: 'Allumez votre bijou.'),
            const SizedBox(height: 16),
            const _Step(number: '2', text: 'Posez-le à côté de ce téléphone.'),
            const SizedBox(height: 16),
            const _Step(number: '3', text: 'Appuyez sur le bouton ci-dessous.'),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: brand,
          child: Text(
            number,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
      ],
    );
  }
}
