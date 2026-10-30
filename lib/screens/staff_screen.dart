import 'package:flutter/material.dart';

import '../database/user_repository.dart';
import '../models/app_user.dart';
import '../session/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/manager_pin_dialog.dart';
import '../widgets/pin_keypad.dart';

/// add staff, change their pin, and deactivate the ones who have left
///
/// a fresh install has only the seeded manager, so without this screen there is
/// no way to give a barista their own pin
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final _users = UserRepository();

  List<AppUser> _staff = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final staff = await _users.getAll();
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final result = await showDialog<_StaffFormResult>(
      context: context,
      builder: (_) => const _StaffFormDialog(),
    );
    if (result == null) return;

    final pin = await _askForPin('Choose a PIN for ${result.name}');
    if (pin == null) return;

    try {
      await _users.createUser(
        name: result.name,
        role: result.role,
        pin: pin,
      );
      await _reload();
      if (!mounted) return;
      _say('${result.name} added');
    } on DuplicatePinException {
      _say('That PIN is already used by someone else', isError: true);
    }
  }

  Future<void> _edit(AppUser user) async {
    final result = await showDialog<_StaffFormResult>(
      context: context,
      builder: (_) => _StaffFormDialog(existing: user),
    );
    if (result == null) return;

    try {
      await _users.updateUser(
        userId: user.userId,
        name: result.name,
        role: result.role,
      );
      await _reload();
    } on LastManagerException {
      _say(
        'This is the only active Manager — someone has to be able to manage '
        'the system',
        isError: true,
      );
    }
  }

  Future<void> _changePin(AppUser user) async {
    final isMe = user.userId == Session.currentUser?.userId;

    if (isMe) {
      // your own pin needs the current one, otherwise anyone who finds the tablet
      // unlocked could change it and lock you out of your own account
      final verified = await showDialog<bool>(
        context: context,
        builder: (_) => _VerifyPinDialog(user: user),
      );
      if (verified != true) return;
    } else {
      // resetting someone else's pin can't ask for theirs, they have forgotten it,
      // so it takes manager approval instead
      final manager = await ManagerPinDialog.show(
        context,
        'Reset the PIN for ${user.name}?',
      );
      if (manager == null) return;
    }
    if (!mounted) return;

    final pin = await _askForPin('New PIN for ${user.name}');
    if (pin == null) return;

    try {
      await _users.updatePin(user.userId, pin);
      if (!mounted) return;
      _say('PIN changed for ${user.name}');
    } on DuplicatePinException {
      _say('That PIN is already used by someone else', isError: true);
    }
  }

  Future<void> _toggleActive(AppUser user) async {
    if (user.isActive && user.userId == Session.currentUser?.userId) {
      _say('You cannot deactivate the account you are signed in with',
          isError: true);
      return;
    }

    try {
      await _users.setActive(user.userId, !user.isActive);
      await _reload();
    } on LastManagerException {
      _say(
        'This is the only active Manager — deactivating them would lock '
        'everyone out',
        isError: true,
      );
    }
  }

  /// asks for a pin twice, same two-phase flow as the first-launch screen
  Future<String?> _askForPin(String prompt) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PinSetDialog(prompt: prompt),
    );
  }

  void _say(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? AppColors.danger : null,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add staff'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _staff.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = _staff[index];
                final isMe = user.userId == Session.currentUser?.userId;

                return ListTile(
                  leading: Icon(
                    user.isManager
                        ? Icons.manage_accounts_outlined
                        : Icons.person_outline,
                    color: user.isActive
                        ? AppColors.inkMuted
                        : AppColors.inkDisabled,
                  ),
                  title: Text(
                    user.name + (isMe ? ' (you)' : ''),
                    style: TextStyle(
                      color: user.isActive
                          ? AppColors.inkBody
                          : AppColors.inkDisabled,
                    ),
                  ),
                  subtitle: Text(
                    user.isActive
                        ? user.role.dbValue
                        : '${user.role.dbValue} · deactivated',
                  ),
                  onTap: user.isActive ? () => _edit(user) : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (user.isActive)
                        TextButton(
                          onPressed: () => _changePin(user),
                          child: const Text('Change PIN'),
                        ),
                      TextButton(
                        onPressed: () => _toggleActive(user),
                        child: Text(
                          user.isActive ? 'Deactivate' : 'Reactivate',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _StaffFormResult {
  const _StaffFormResult(this.name, this.role);
  final String name;
  final UserRole role;
}

/// name and role, the pin is asked for separately on the keypad
class _StaffFormDialog extends StatefulWidget {
  const _StaffFormDialog({this.existing});

  final AppUser? existing;

  @override
  State<_StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<_StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.existing?.name);
  late UserRole _role = widget.existing?.role ?? UserRole.barista;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _StaffFormResult(_nameCtrl.text.trim(), _role),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit ${widget.existing!.name}' : 'New staff member'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment(
                    value: UserRole.barista,
                    label: Text('Barista'),
                  ),
                  ButtonSegment(
                    value: UserRole.manager,
                    label: Text('Manager'),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Managers can change settings, void sales and see reports. '
                'Baristas can sell, record losses and close their shift.',
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Next'),
        ),
      ],
    );
  }
}

/// checks the current pin belongs to [user], returns true when it does
///
/// deliberately not reusing the manager approval dialog, that accepts any
/// manager's pin and this has to be yours
class _VerifyPinDialog extends StatefulWidget {
  const _VerifyPinDialog({required this.user});

  final AppUser user;

  @override
  State<_VerifyPinDialog> createState() => _VerifyPinDialogState();
}

class _VerifyPinDialogState extends State<_VerifyPinDialog> {
  final _users = UserRepository();
  String? _error;
  bool _checking = false;

  Future<void> _onPinEntered(String pin) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    final match = await _users.findByPin(pin);
    if (!mounted) return;

    if (match == null || match.userId != widget.user.userId) {
      setState(() {
        _checking = false;
        _error = 'That is not your current PIN';
      });
      return;
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter your current PIN'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Confirm it is you before changing your PIN.'),
            const SizedBox(height: AppSpacing.lg),
            PinKeypad(onCompleted: _onPinEntered, errorMessage: _error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// enter a pin then confirm it, returns the pin or null if cancelled
class _PinSetDialog extends StatefulWidget {
  const _PinSetDialog({required this.prompt});

  final String prompt;

  @override
  State<_PinSetDialog> createState() => _PinSetDialogState();
}

class _PinSetDialogState extends State<_PinSetDialog> {
  String? _firstEntry;
  String? _error;

  bool get _isConfirming => _firstEntry != null;

  void _onPinEntered(String pin) {
    if (!_isConfirming) {
      // 0000 is the seeded default and would trip the first-launch screen
      if (pin == UserRepository.defaultManagerPin) {
        setState(() => _error = 'Pick a PIN other than 0000');
        return;
      }
      setState(() {
        _firstEntry = pin;
        _error = null;
      });
      return;
    }

    if (pin != _firstEntry) {
      setState(() {
        _firstEntry = null;
        _error = 'PINs did not match — try again';
      });
      return;
    }

    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isConfirming ? 'Confirm the PIN' : widget.prompt),
      content: SingleChildScrollView(
        child: PinKeypad(onCompleted: _onPinEntered, errorMessage: _error),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
