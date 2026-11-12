import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

String? _countryOf(BuildContext context) =>
    View.of(context).platformDispatcher.locale.countryCode;

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  Future<void> _add(BuildContext context, EmergencyContact contact) async {
    final state = AppScope.of(context);
    final contacts = state.config.contacts;
    if (contacts.any((c) => c.phone == contact.phone)) {
      showMessage(context, 'Ce numéro est déjà dans votre liste.');
      return;
    }
    // Pas de message : le contact apparaît aussitôt dans la liste.
    await state.updateConfig(
      state.config.copyWith(contacts: [...contacts, contact]),
    );
  }

  Future<void> _remove(BuildContext context, EmergencyContact contact) async {
    final state = AppScope.of(context);
    final ok = await confirm(
      context,
      title: 'Retirer ${contact.name} ?',
      message: "Cette personne ne recevra plus vos alertes.",
      yes: 'Oui, retirer',
    );
    if (!ok) return;
    await state.updateConfig(
      state.config.copyWith(
        contacts: [
          for (final c in state.config.contacts)
            if (c.phone != contact.phone) c,
        ],
      ),
    );
  }

  Future<void> _pickFromAddressBook(BuildContext context) async {
    final country = _countryOf(context);
    final Contact? picked;
    try {
      final permission = await FlutterContacts.permissions.request(PermissionType.read);
      if (permission != PermissionStatus.granted && permission != PermissionStatus.limited) {
        if (context.mounted) {
          showMessage(
            context,
            "L'application n'a pas accès à votre répertoire. Vous pouvez saisir le numéro à la main.",
          );
        }
        return;
      }
      picked = await FlutterContacts.native.showPicker(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
    } on PlatformException {
      if (context.mounted) {
        showMessage(context, "Impossible d'ouvrir le répertoire. Saisissez le numéro à la main.");
      }
      return;
    }
    if (picked == null || !context.mounted) return;

    final name = picked.displayName ?? '';
    final phones = {
      for (final p in picked.phones) ?normalizePhone(p.number, countryCode: country),
    }.toList();
    if (phones.isEmpty) {
      showMessage(context, "$name n'a pas de numéro de téléphone valide.");
      return;
    }
    final phone = phones.length == 1
        ? phones.first
        : await _choosePhone(context, name, phones);
    if (phone == null || !context.mounted) return;
    await _add(context, EmergencyContact(name: name, phone: phone));
  }

  Future<String?> _choosePhone(BuildContext context, String name, List<String> phones) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Quel numéro utiliser pour $name ?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              for (final phone in phones) ...[
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, phone),
                  child: Text(formatPhone(phone)),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _typeNumber(BuildContext context) async {
    final contact = await Navigator.push(
      context,
      MaterialPageRoute<EmergencyContact>(builder: (_) => const _ManualContactScreen()),
    );
    if (contact != null && context.mounted) await _add(context, contact);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final contacts = AppScope.of(context).config.contacts;
    final full = contacts.length >= maxContacts;

    return Scaffold(
      appBar: AppBar(title: const Text("Contacts d'urgence")),
      body: PageBody(
        actions: full
            ? const []
            : [
                FilledButton.icon(
                  onPressed: () => _pickFromAddressBook(context),
                  icon: const Icon(Icons.contacts),
                  label: const Text('Choisir dans mon répertoire'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _typeNumber(context),
                  icon: const Icon(Icons.dialpad),
                  label: const Text('Saisir un numéro'),
                ),
              ],
        children: [
          Text(
            contacts.isEmpty
                ? "Ces personnes recevront un message avec votre position quand vous appuierez sur le bouton du bijou.\n\nAjoutez votre premier contact avec les boutons ci-dessous."
                : 'Ces personnes recevront un message avec votre position quand vous appuierez sur le bouton du bijou.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 20),
          for (final contact in contacts) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 40, color: brand),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(contact.name, style: text.titleMedium),
                          Text(formatPhone(contact.phone), style: text.bodyLarge),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _remove(context, contact),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFA3261E)),
                      child: const Text('Retirer'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (full)
            Text(
              'Vous avez atteint le maximum de $maxContacts contacts. Retirez-en un pour en ajouter un autre.',
              style: text.bodyMedium,
            ),
        ],
      ),
    );
  }
}

class _ManualContactScreen extends StatefulWidget {
  const _ManualContactScreen();

  @override
  State<_ManualContactScreen> createState() => _ManualContactScreenState();
}

class _ManualContactScreenState extends State<_ManualContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      EmergencyContact(
        name: _name.text.trim(),
        phone: normalizePhone(_phone.text, countryCode: _countryOf(context))!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const fieldStyle = TextStyle(fontSize: 24);
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau contact')),
      body: Form(
        key: _formKey,
        child: PageBody(
          actions: [
            FilledButton(onPressed: _save, child: const Text('Enregistrer')),
          ],
          children: [
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              style: fieldStyle,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nom de la personne'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Indiquez le nom de la personne.' : null,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _phone,
              style: fieldStyle,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numéro de téléphone portable',
              ),
              validator: (v) => normalizePhone(v ?? '') == null
                  ? 'Ce numéro ne semble pas correct. Vérifiez-le.'
                  : null,
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
    );
  }
}
