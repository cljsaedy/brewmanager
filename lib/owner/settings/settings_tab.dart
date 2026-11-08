import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/backup_files.dart';
import '../../data/backup_store.dart';
import '../../data/database_helper.dart';
import '../../data/email_settings_store.dart';
import '../../data/owner_pin_store.dart';
import '../../email/outbox_sender.dart';
import '../../logic/business_day.dart';
import '../../logic/formatting.dart';
import '../../security/key_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/message_box.dart';
import '../create_pin_screen.dart';
import '../recovery_code_screen.dart';

// owner settings: emails and ai keys (feature 9), then pin and backup (feature 11)
// the setup wizard shows only the emails and keys part, with skip and save and continue
class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.store,
    this.pins,
    this.backup,
    this.sender,
    this.files = const DeviceBackupFiles(),
    this.restoreDatabase = DatabaseHelper.replaceWith,
    this.onWizardNext,
  });

  final EmailSettingsStore store;
  // the pin and backup part only shows when these are given (the owner section gives them)
  final OwnerPinStore? pins;
  final BackupStore? backup;
  // sends a new recovery code email right away
  final OutboxSender? sender;
  // where backups are saved and picked, tests pass a fake
  final BackupFiles files;
  // puts a restored db in place, tests pass a fake so the real db file is never touched
  final Future<void> Function(Uint8List bytes) restoreDatabase;
  // setup wizard mode: called after save and continue or skip, null = normal owner settings
  final VoidCallback? onWizardNext;

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
  // when the last backup was made, utc iso text, null = never
  String? _lastBackup;
  // true while a backup or restore runs, its buttons are off
  bool _busy = false;

  bool get _inWizard => widget.onWizardNext != null;

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
    final lastBackup = await widget.backup?.lastBackup();
    // mounted = the tab is still open
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _lastBackup = lastBackup;
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
      if (_inWizard) {
        widget.onWizardNext!();
        return;
      }
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
                            Text(
                              _inWizard ? 'Emails & keys' : 'Settings',
                              style: text.titleLarge,
                            ),
                            Text(
                              _inWizard
                                  ? 'Step 2 of 3. You can skip this and set '
                                        'them later in owner Settings.'
                                  : 'Emails and AI keys, PIN, backup and restore.',
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (_inWizard) ...[
                        TextButton(
                          key: const Key('wizard_skip'),
                          onPressed: _saving ? null : widget.onWizardNext,
                          child: const Text('Skip'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton(
                        key: const Key('save_settings'),
                        onPressed: _saving ? null : _save,
                        child: Text(_inWizard ? 'Save and continue' : 'Save'),
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
                        if (widget.pins != null && !_inWizard) ...[
                          const SizedBox(height: 20),
                          const Divider(height: 1),
                          const SizedBox(height: 20),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _pinPart(text)),
                              const SizedBox(width: 24),
                              Expanded(child: _backupPart(text)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // change pin: no old pin asked, the owner is already inside the owner section (decided with the developer)
  // the new pin gets a new recovery code shown once, and emailed if an owner email is set
  Future<void> _changePin() async {
    final pins = widget.pins!;
    // taken now, this tab is under the pin screens while they are open
    final messenger = ScaffoldMessenger.of(context);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePinScreen(
          store: pins,
          title: 'New owner PIN',
          onCodeSaved: (screenContext, _) {
            Navigator.of(screenContext).pop();
            _afterNewCode(messenger, 'PIN changed.');
          },
        ),
      ),
    );
  }

  // a new recovery code without changing the pin, the old code stops working
  Future<void> _newRecoveryCode() async {
    final sure = await _confirm(
      title: 'Make a new recovery code?',
      body:
          'The old code stops working. The new one is shown once, and '
          'emailed to the owner if an owner email is set.',
      yes: 'Make new code',
      yesKey: 'confirm_new_code',
    );
    if (sure != true || !mounted) return;

    final pins = widget.pins!;
    final messenger = ScaffoldMessenger.of(context);
    final code = await pins.newRecoveryCode();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecoveryCodeScreen(
          code: code,
          db: pins.db,
          onSaved: (screenContext) {
            Navigator.of(screenContext).pop();
            _afterNewCode(messenger, 'New recovery code made.');
          },
        ),
      ),
    );
  }

  // the code email was queued with the new code, send it now instead of waiting for the next app start
  // unawaited = it runs on its own and never throws, the outbox shows how it went
  void _afterNewCode(ScaffoldMessengerState messenger, String done) {
    final sender = widget.sender;
    if (sender != null) unawaited(sender.sendAll());
    final hasOwner = (_settings?.ownerEmail ?? '').isNotEmpty;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            hasOwner
                ? '$done The recovery code was emailed to the owner too.'
                : done,
          ),
        ),
      );
  }

  // back up (rule 13): the whole db file, saved where the owner picks
  Future<void> _backUp() async {
    final backup = widget.backup!;
    setState(() => _busy = true);
    try {
      final snapshot = await backup.snapshot();
      final name = 'brewmanager-backup-${dateText(DateTime.now())}.db';
      final saved = await widget.files.save(name, snapshot.bytes);
      if (!saved) {
        // cancelled, so the last real backup time stays
        await backup.undoSnapshot(snapshot.oldTime);
        return;
      }
      _message('Backup saved as $name.');
    } catch (error) {
      _message('The backup could not be saved: $error');
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  // restore (rule 13): pick a file, check it is a brewmanager db, ask, then replace everything
  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.files.pick();
      if (bytes == null || !mounted) return;
      final check = await BackupStore.check(bytes);
      if (!mounted) return;
      if (!check.isValid) {
        setState(
          () => _error =
              'That file is not a BrewManager backup, so nothing was changed.',
        );
        return;
      }

      final sure = await _confirm(
        title: 'Restore this backup?',
        body:
            'This will replace all current data with the backup from '
            '${_backupDate(check)}. Continue?',
        yes: 'Replace everything',
        yesKey: 'confirm_restore',
      );
      if (sure != true || !mounted) return;

      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      await widget.restoreDatabase(bytes);
      // every open screen still holds the old db, so the owner section closes
      // and the barista side starts fresh with the restored one
      navigator.popUntil((route) => route.isFirst);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Backup restored. The owner PIN is now the one from the backup. '
              'API keys stay as they were on this tablet.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
    } catch (error) {
      _message('The backup could not be restored: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // like "Mon, Nov 9 at 3:15pm", or the newest day when the copy has no backup time
  static String _backupDate(BackupCheck check) {
    final made = check.madeAt;
    if (made != null) return _timeText(made);
    final newest = check.newestDay;
    if (newest != null) {
      return 'a copy with days up to ${formatLongDate(newest)}';
    }
    return 'a copy with no counts yet';
  }

  // utc iso text in the tablet's time, like "Mon, Nov 9 at 3:15pm"
  static String _timeText(String utc) {
    final local = DateTime.parse(utc).toLocal();
    return '${formatLongDate(dateText(local))} at ${formatTime(local)}';
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String yes,
    required String yesKey,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key(yesKey),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(yes),
          ),
        ],
      ),
    );
  }

  Widget _pinPart(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Owner PIN', style: text.titleMedium),
        Text(
          'A new PIN or code is shown once. If an owner email is set, the '
          'recovery code is emailed too.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('change_pin'),
              onPressed: _busy ? null : _changePin,
              icon: const Icon(Icons.pin_outlined),
              label: const Text('Change PIN'),
            ),
            OutlinedButton.icon(
              key: const Key('new_recovery_code'),
              onPressed: _busy ? null : _newRecoveryCode,
              icon: const Icon(Icons.key_outlined),
              label: const Text('New recovery code'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _backupPart(TextTheme text) {
    final last = _lastBackup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Backup', style: text.titleMedium),
        Text(
          last == null
              ? 'Last backup: never.'
              : 'Last backup: ${_timeText(last)}.',
          key: const Key('last_backup'),
          style: text.bodySmall,
        ),
        Text(
          'A backup has all counts, reports, stock and menu, and the PIN. '
          'It never has the API keys.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('back_up'),
              onPressed: _busy || widget.backup == null ? null : _backUp,
              icon: const Icon(Icons.save_alt_outlined),
              label: const Text('Back up'),
            ),
            OutlinedButton.icon(
              key: const Key('restore'),
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restore_outlined),
              label: const Text('Restore'),
            ),
          ],
        ),
      ],
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
        if (settings.lastAiTry != null) _lastAiTry(text, settings.lastAiTry!),
      ],
    );
  }

  // what happened the last time the ai summary was tried, so a failure says why
  // green when it was used, amber otherwise
  Widget _lastAiTry(TextTheme text, String lastTry) {
    final used = lastTry == 'ai';
    return Container(
      key: const Key('last_ai_try'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: used ? AppColors.okBg : AppColors.warnBg,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Text(
        used
            ? 'Last AI summary: used in the report.'
            : 'Last AI summary: not used ($lastTry).',
        style: text.bodySmall?.copyWith(
          color: used ? AppColors.okText : AppColors.warnText,
        ),
      ),
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
