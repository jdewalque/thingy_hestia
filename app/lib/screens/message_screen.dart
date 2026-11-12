import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _message = TextEditingController();
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final config = AppScope.of(context).config;
    _name.text = config.wearerName;
    _lastName = config.wearerName;
    _message.text = config.message;
    _name.addListener(_onNameChanged);
    _message.addListener(() => setState(() {}));
  }

  String _lastName = '';

  /// Tant que le message n'a pas été personnalisé, il suit le nom saisi.
  void _onNameChanged() {
    final name = _name.text.trim();
    if (_message.text.isEmpty || _message.text == defaultMessage(_lastName)) {
      _message.text = defaultMessage(name);
    }
    _lastName = name;
  }

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = AppScope.of(context);
    await state.updateConfig(
      state.config.copyWith(
        wearerName: _name.text.trim(),
        message: _message.text.trim(),
      ),
    );
    if (!mounted) return;
    await showMessage(context, 'Vos réglages sont enregistrés.');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const fieldStyle = TextStyle(fontSize: 22);

    return Scaffold(
      appBar: AppBar(title: const Text('Nom et message')),
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
              decoration: const InputDecoration(
                labelText: 'Votre prénom et votre nom',
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Indiquez votre nom.' : null,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _message,
              style: fieldStyle,
              minLines: 3,
              maxLines: 5,
              maxLength: maxMessageLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message envoyé à vos contacts',
                alignLabelWithHint: true,
                counterStyle: TextStyle(fontSize: 16),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Écrivez un message.' : null,
            ),
            const SizedBox(height: 16),
            Text('Vos contacts recevront :', style: text.titleMedium),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE3EFEE),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_message.text.trim().isEmpty ? '…' : _message.text.trim()}\n'
                'Sa position : (lien vers la carte)',
                style: text.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
