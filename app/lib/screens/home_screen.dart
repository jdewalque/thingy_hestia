import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'contacts_screen.dart';
import 'message_screen.dart';
import 'test_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _unpair(BuildContext context) async {
    final state = AppScope.of(context);
    final ok = await confirm(
      context,
      title: 'Changer de bijou ?',
      message: "Ce téléphone ne sera plus relié au bijou actuel. Vos contacts et votre message sont conservés.",
      yes: 'Oui, changer de bijou',
    );
    if (ok) await state.unpair();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final config = state.config;
    final count = config.contacts.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(state.isDemo ? 'Mon bijou (démonstration)' : 'Mon bijou'),
      ),
      body: PageBody(
        children: [
          _StatusCard(state: state),
          if (!config.isComplete) ...[
            const SizedBox(height: 16),
            _Notice(
              icon: Icons.warning_amber_rounded,
              color: warnOrange,
              text: count == 0
                  ? "Votre bijou ne peut encore prévenir personne. Ajoutez au moins un contact d'urgence."
                  : "Indiquez votre nom pour que vos contacts sachent qui a besoin d'aide.",
            ),
          ] else if (state.pendingSync) ...[
            const SizedBox(height: 16),
            const _Notice(
              icon: Icons.sync,
              color: warnOrange,
              text: "Vos derniers réglages seront envoyés au bijou dès qu'il sera près du téléphone.",
            ),
          ],
          const SizedBox(height: 24),
          _MenuTile(
            icon: Icons.people_alt,
            title: "Mes contacts d'urgence",
            subtitle: switch (count) {
              0 => 'Aucun contact',
              1 => '1 contact',
              _ => '$count contacts',
            },
            onTap: () => _open(context, const ContactsScreen()),
          ),
          const SizedBox(height: 16),
          _MenuTile(
            icon: Icons.sms,
            title: 'Mon nom et mon message',
            subtitle: config.wearerName.isEmpty
                ? 'À compléter'
                : config.wearerName,
            onTap: () => _open(context, const MessageScreen()),
          ),
          const SizedBox(height: 16),
          _MenuTile(
            icon: Icons.notifications_active,
            title: "Tester l'alerte",
            subtitle: 'Vérifier que tout fonctionne',
            onTap: () => _open(context, const TestScreen()),
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () => _unpair(context),
              child: const Text('Changer de bijou'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final connected = state.connected;
    final status = state.status;
    final color = connected ? okGreen : warnOrange;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connected ? Icons.check_circle : Icons.bluetooth_searching,
                  size: 48,
                  color: color,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    connected ? 'Bijou connecté' : 'Bijou hors de portée',
                    style: text.titleLarge?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!connected)
              Text(
                "Approchez le bijou du téléphone pour le régler. Il continue d'envoyer vos alertes même loin du téléphone.",
                style: text.bodyMedium,
              )
            else if (status != null) ...[
              _StatusLine(
                icon: _batteryIcon(status.battery),
                text: status.battery == null
                    ? 'Batterie : inconnue'
                    : 'Batterie : ${status.battery} %',
                warning: (status.battery ?? 100) <= 20
                    ? 'Pensez à recharger le bijou.'
                    : null,
              ),
              const SizedBox(height: 8),
              _StatusLine(
                icon: Icons.signal_cellular_alt,
                text: switch (status.lte) {
                  LteState.connected => 'Réseau mobile : connecté',
                  LteState.searching => 'Réseau mobile : recherche…',
                  LteState.off => 'Réseau mobile : absent',
                },
                warning: status.lte == LteState.off
                    ? "Sans réseau, le bijou ne peut pas envoyer d'alerte."
                    : null,
              ),
            ] else
              Text("Lecture de l'état du bijou…", style: text.bodyMedium),
          ],
        ),
      ),
    );
  }

  static IconData _batteryIcon(int? level) {
    if (level == null) return Icons.battery_unknown;
    if (level <= 20) return Icons.battery_alert;
    if (level <= 60) return Icons.battery_4_bar;
    return Icons.battery_full;
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.text, this.warning});

  final IconData icon;
  final String text;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 30, color: warning == null ? ink : warnOrange),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: style),
              if (warning != null)
                Text(
                  warning!,
                  style: style?.copyWith(
                    color: warnOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 34, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Row(
            children: [
              Icon(icon, size: 44, color: brand),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: text.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 36, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}
