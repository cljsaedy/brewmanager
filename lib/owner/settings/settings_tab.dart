import 'package:flutter/material.dart';

import '../../data/email_settings_store.dart';
import '../../security/key_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/message_box.dart';

// owner settings, for now only the email & ai keys part (feature 9)
// change pin, backup and restore come in feature 11
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.store});

  final EmailSettingsStore store;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  // null while loading
  EmailSettings? _settings;

  final TextEditingController _ownerBox = TextEditingController();
  final TextEditingController _senderBox = TextEditingController();
  // the key boxes always start empty, a saved key is never shown back
  final Map<ApiKey, TextEditingController> _keyBoxes = {
    for (final key in ApiKey.values) key: TextEditingController(),
  };

  String? _error;
  // true while saving, the save button is off so a double tap saves once
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ownerBox.dispose();
    _senderBox.dispose();
    for (final box in _keyBoxes.values) {
      box.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await widget.store.load();
    // mounted = the tab is still open
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _ownerBox.text = settings.ownerEmail ?? '';
      _senderBox.text = settings.senderEmail ?? '';
      for (final box in _keyBoxes.values) {
        box.clear();
      }
    });
  }

  // saves both emails, and only the keys that were typed (an empty key box keeps the saved key)
  Future<void> _save() async {
    final owner = _ownerBox.text.trim();
    final sender = _senderBox.text.trim();
    for (final email in [owner, sender]) {
      if (email.isNotEmpty && !looksLikeEmail(email)) {
        setState(() => _error = '"$email" does not look like an email.');
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await widget.store.saveEmails(ownerEmail: owner, senderEmail: sender);
      for (final entry in _keyBoxes.entries) {
        if (entry.value.text.trim().isEmpty) continue;
        await widget.store.saveKey(entry.key, entry.value.text);
      }
      await _load();
      _message('Saved.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(ApiKey key) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove the ${_label(key)}?'),
        content: Text(_removeNote(key)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const Key('confirm_remove'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await widget.store.removeKey(key);
    await _load();
    _message('${_label(key)} removed.');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  static String _label(ApiKey key) {
    return switch (key) {
      ApiKey.mailjetKey => 'Mailjet API key',
      ApiKey.mailjetSecret => 'Mailjet secret key',
      ApiKey.groqKey => 'Groq API key',
    };
  }

  // what stops working without the key, so the owner knows before removing it
  static String _removeNote(ApiKey key) {
    return key == ApiKey.groqKey
        ? 'Reports will use the template summary until a new key is saved.'
        : 'Emails will wait in the outbox until a new key is saved.';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final settings = _settings;

    return Card(
      child: settings == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Email & AI keys', style: text.titleLarge),
                            Text(
                              'Change PIN, backup and restore come in Feature 11.',
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        key: const Key('save_settings'),
                        onPressed: _saving ? null : _save,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          MessageBox(text: _error!, isError: true),
                          const SizedBox(height: 14),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _emailPart(text)),
                            const SizedBox(width: 24),
                            Expanded(child: _keyPart(text, settings)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _emailPart(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Emails', style: text.titleMedium),
        const SizedBox(height: 10),
        TextField(
          key: const Key('owner_email_field'),
          controller: _ownerBox,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Owner email',
            helperText: 'The daily report goes here.',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('sender_email_field'),
          controller: _senderBox,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Sender email',
            helperText: 'Must be a verified sender in your Mailjet account.',
          ),
        ),
      ],
    );
  }

  Widget _keyPart(TextTheme text, EmailSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Keys', style: text.titleMedium),
        Text(
          "Kept in the tablet's secure storage, never in the database or "
          'backups. A saved key is never shown again.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 10),
        for (final key in ApiKey.values) ...[
          _keyField(key, settings.hasKey(key)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // obscureText = dots instead of letters, so the key isnt readable over a shoulder
  Widget _keyField(ApiKey key, bool saved) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: Key('${key.storageName}_field'),
            controller: _keyBoxes[key],
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: _label(key),
              helperText: saved
                  ? 'Saved. Type a new one to replace it.'
                  : 'Not set.',
              helperStyle: TextStyle(
                color: saved ? AppColors.okText : AppColors.textMuted,
              ),
            ),
          ),
        ),
        if (saved) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              key: Key('${key.storageName}_remove'),
              onPressed: _saving ? null : () => _remove(key),
              child: const Text('Remove'),
            ),
          ),
        ],
      ],
    );
  }
}
