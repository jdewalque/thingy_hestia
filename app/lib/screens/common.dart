import 'package:material_ui/material_ui.dart';

import '../jewel/jewel_link.dart';

/// Explique une erreur en français simple, avec ce qu'il faut faire.
String describeError(Object error) {
  if (error is! JewelException) {
    return "Une erreur s'est produite. Veuillez réessayer.";
  }
  return switch (error.error) {
    JewelError.bluetoothOff => "Le Bluetooth de ce téléphone est éteint. Activez-le dans les réglages du téléphone, puis réessayez.",
    JewelError.permission => "L'application n'a pas l'autorisation d'utiliser le Bluetooth. Autorisez-la dans les réglages du téléphone, puis réessayez.",
    JewelError.notFound => "Aucun bijou trouvé. Vérifiez qu'il est allumé et tout près du téléphone, puis réessayez.",
    JewelError.notConnected =>
      "Le bijou est hors de portée. Approchez-le du téléphone, puis réessayez.",
    JewelError.timeout =>
      "Le bijou n'a pas répondu. Approchez-le du téléphone, puis réessayez.",
    JewelError.noNetwork => "Le bijou ne capte pas le réseau mobile. Déplacez-vous près d'une fenêtre ou à l'extérieur, puis réessayez.",
    JewelError.noContact => "Le bijou n'a encore aucun contact d'urgence. Ajoutez-en un, puis réessayez.",
    JewelError.smsFailed => "Le bijou n'a pas réussi à envoyer le message. Vérifiez que sa carte SIM permet d'envoyer des SMS, puis réessayez.",
    JewelError.busy =>
      "Le bijou envoie déjà une alerte. Attendez une minute, puis réessayez.",
    JewelError.rejected =>
      "Le bijou n'a pas pu effectuer cette action. Veuillez réessayer.",
  };
}

/// Affiche un message qui reste à l'écran jusqu'à ce que l'utilisateur
/// appuie sur « OK » : il a tout le temps de le lire.
Future<void> showMessage(BuildContext context, String text) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(text),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Demande une confirmation avec deux gros boutons explicites.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String yes,
  String no = 'Annuler',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(yes),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(no),
            ),
          ],
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Page standard : contenu défilant et boutons d'action fixés en bas.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.actions = const []});

  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: children,
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  for (final (i, action) in actions.indexed) ...[
                    if (i > 0) const SizedBox(height: 12),
                    action,
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
