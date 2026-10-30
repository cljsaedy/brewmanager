import 'dart:io';

import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../session/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/empty_state.dart';
import '../widgets/manager_pin_dialog.dart';

/// copies the database out and puts it back, the whole system is one file so a
/// backup is a copy of that file
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _service = BackupService();

  List<File> _backups = [];
  String? _folderPath;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final dir = await _service.backupDirectory();
    final backups = await _service.listBackups();
    if (!mounted) return;
    setState(() {
      _folderPath = dir.path;
      _backups = backups;
      _working = false;
    });
  }

  Future<void> _createBackup() async {
    if (_working) return;
    setState(() => _working = true);

    try {
      final file = await _service.createBackup();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backed up to ${file.uri.pathSegments.last}')),
      );
    } catch (e) {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('Backup failed: $e'),
        ),
      );
    }
  }

  Future<void> _restore(File backup) async {
    if (_working) return;

    final taken = _timeLabel(backup.statSync().modified);

    // restoring throws away everything recorded since the backup, so it needs
    // a manager pin as well as a confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Restore this backup?'),
        content: Text(
          'The database will be replaced with the backup taken $taken.\n\n'
          'Every sale, delivery, declared loss and closing count recorded '
          'since then will be lost. This cannot be undone from inside the app, '
          'though a copy of the current database will be saved first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final manager = await ManagerPinDialog.show(
      context,
      'Replace the current database with the backup taken $taken?',
    );
    if (manager == null) return;

    setState(() => _working = true);

    try {
      final safetyCopy = await _service.restore(backup);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Database restored'),
          content: Text(
            'The backup is now the live database.\n\n'
            'The database as it was a moment ago was saved as '
            '${safetyCopy.uri.pathSegments.last}, so this can be reversed.\n\n'
            'You will be signed out, because the restored database may have '
            'different staff and PINs.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );

      // every screen's loaded data is now stale, and the pins may have changed,
      // so the only safe thing is to start again from the lock screen
      Session.logOut();
    } on NotADatabaseException {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: const Text(
            'That file is not a BrewManager database — nothing was changed',
          ),
        ),
      );
    } catch (e) {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('Restore failed: $e'),
        ),
      );
    }
  }

  Future<void> _delete(File backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this backup?'),
        content: Text(backup.uri.pathSegments.last),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _service.deleteBackup(backup);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _lastBackupLabel(),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Everything is kept in one database file on this '
                        'tablet, so a backup is a copy of that file.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _folderPath ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _working ? null : _createBackup,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Back up now'),
                ),
              ],
            ),
          ),
          // the only copy of the cafe's records lives on one tablet, so a stale
          // backup is worth saying out loud rather than leaving to be noticed
          if (_isBackupStale) _buildStaleWarning(),
          const Divider(height: 1),
          Expanded(
            child: _backups.isEmpty
                ? const EmptyState(
                    icon: Icons.storage_outlined,
                    title: 'No backups yet',
                    message: 'Take one now, and again after each busy week. '
                        'A backup can be copied off the tablet over USB.',
                  )
                : ListView.separated(
                    itemCount: _backups.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final backup = _backups[index];
                      final stat = backup.statSync();
                      return ListTile(
                        leading: const Icon(Icons.storage_outlined),
                        title: Text(backup.uri.pathSegments.last),
                        subtitle: Text(
                          '${_sizeLabel(stat.size)} · '
                          '${_timeLabel(stat.modified)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // outlined and red, restoring throws away everything
                            // recorded since, it shouldn't look like a default
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, AppSizes.minTarget),
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(
                                  color: AppColors.danger,
                                ),
                              ),
                              icon: const Icon(Icons.restore),
                              label: const Text('Restore'),
                              onPressed:
                                  _working ? null : () => _restore(backup),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed:
                                  _working ? null : () => _delete(backup),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// when the newest backup was taken, null when there are none
  DateTime? get _lastBackupAt =>
      _backups.isEmpty ? null : _backups.first.statSync().modified;

  /// a week without a backup, worth a nudge on a deployed tablet
  bool get _isBackupStale {
    final last = _lastBackupAt;
    if (last == null) return false;
    return DateTime.now().difference(last).inDays >= 7;
  }

  String _lastBackupLabel() {
    final last = _lastBackupAt;
    if (last == null) return 'Never backed up';

    final gap = DateTime.now().difference(last);
    if (gap.inMinutes < 2) return 'Backed up just now';
    if (gap.inHours < 1) return 'Backed up ${gap.inMinutes} minutes ago';
    if (gap.inHours < 24) {
      return 'Backed up ${gap.inHours} hour${gap.inHours == 1 ? '' : 's'} ago';
    }
    return 'Backed up ${gap.inDays} day${gap.inDays == 1 ? '' : 's'} ago';
  }

  Widget _buildStaleWarning() {
    return Container(
      width: double.infinity,
      color: AppColors.caution.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            color: AppColors.cautionText,
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Text(
              'It has been over a week since the last backup. If this tablet '
              'is lost or wiped, everything since then goes with it.',
              style: TextStyle(color: AppColors.cautionText),
            ),
          ),
        ],
      ),
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _timeLabel(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}
