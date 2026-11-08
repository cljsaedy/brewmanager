import 'package:flutter/material.dart';

import '../../data/sent_reports_store.dart';
import '../../email/outbox_sender.dart';
import '../../logic/formatting.dart';
import '../../theme/app_theme.dart';
import '../../widgets/message_box.dart';
import '../../widgets/status_chip.dart';
import 'email_view.dart';

// shows the html of 1 email, tests pass a simple one since a webview cant run in tests
typedef EmailViewBuilder = Widget Function(String html);

Widget _defaultViewer(String html) => EmailView(html: html);

// the owner's reports tab (feature 10): every daily report and correction email, same content as sent
// left = the list with each email's send status, right = the picked email with resend
class ReportsTab extends StatefulWidget {
  const ReportsTab({
    super.key,
    required this.store,
    required this.sender,
    this.viewer = _defaultViewer,
  });

  final SentReportsStore store;
  final OutboxSender sender;
  final EmailViewBuilder viewer;

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  // width of the email list, the email gets the rest
  static const double _listWidth = 290;

  // null while loading
  List<SentReport>? _reports;
  int? _selectedId;
  // true while resend runs, the button is off so it cant be tapped twice
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // reads the list, keeps the picked email if it is still there, else picks the newest
  Future<void> _load() async {
    final reports = await widget.store.list();
    if (!mounted) return;
    setState(() {
      _reports = reports;
      final stillThere = reports.any((report) => report.id == _selectedId);
      if (!stillThere) _selectedId = reports.isEmpty ? null : reports.first.id;
    });
  }

  // resend: queues it again and sends everything waiting, then the list shows the new status
  Future<void> _resend(SentReport report) async {
    setState(() => _sending = true);
    await widget.sender.resend(report.id);
    await _load();
    if (!mounted) return;
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    if (reports == null) {
      return const Card(child: Center(child: CircularProgressIndicator()));
    }
    if (reports.isEmpty) return _empty(context);

    final selected = reports.firstWhere((report) => report.id == _selectedId);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _listWidth, child: _list(context, reports)),
        const SizedBox(width: 12),
        Expanded(child: _details(context, selected)),
      ],
    );
  }

  // shown before the first submit
  Widget _empty(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mail_outline,
              size: 40,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 10),
            Text('No reports yet', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'The daily report shows here after each Submit.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<SentReport> reports) {
    return Card(
      // clip so the picked email's background follows the round corners
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              'Reports',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: [for (final report in reports) _tile(context, report)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, SentReport report) {
    final date = report.businessDate;
    return Material(
      color: report.id == _selectedId ? AppColors.cream : Colors.transparent,
      child: InkWell(
        key: Key('report_${report.id}'),
        onTap: () => setState(() => _selectedId = report.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      date == null ? report.subject : formatLongDate(date),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _statusChip(report.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                report.isDaily ? 'Daily report' : 'Correction',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(EmailStatus status) {
    return switch (status.state) {
      EmailState.sent => const StatusChip(label: 'Sent', tone: ChipTone.ok),
      EmailState.waiting => const StatusChip(
        label: 'Waiting',
        tone: ChipTone.warn,
      ),
      EmailState.failed => const StatusChip(
        label: 'Failed',
        tone: ChipTone.error,
      ),
    };
  }

  // the picked email: its status in words, resend, then the email itself
  Widget _details(BuildContext context, SentReport report) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.subject,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusText(report),
                        key: const Key('report_status_text'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  key: const Key('resend_button'),
                  onPressed: _sending ? null : () => _resend(report),
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(_sending ? 'Sending' : 'Resend'),
                ),
              ],
            ),
          ),
          // why it isnt sent, word for word from mailjet or the app
          if (report.status.state != EmailState.sent &&
              report.status.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: MessageBox(
                key: const Key('report_error'),
                text: report.status.error!,
                isError: report.status.state == EmailState.failed,
              ),
            ),
          const Divider(),
          Expanded(child: widget.viewer(report.html)),
        ],
      ),
    );
  }

  // like "Sent Mon, Nov 2 at 9:42pm" or "Failed after 2 tries"
  String _statusText(SentReport report) {
    final status = report.status;
    switch (status.state) {
      case EmailState.sent:
        final sentAt = report.sentAt;
        if (sentAt == null) return 'Sent';
        final local = DateTime.parse(sentAt).toLocal();
        return 'Sent ${formatLongDate(_dateOnly(local))} at ${formatTime(local)}';
      case EmailState.waiting:
        return status.needsSettings
            ? 'Waiting: set the emails and Mailjet keys in Settings.'
            : 'Waiting for internet. It sends when the app opens, after a submit, or with Resend.';
      case EmailState.failed:
        final tries = report.attempts == 1
            ? '1 try'
            : '${report.attempts} tries';
        return 'Failed after $tries. It is tried again on the next send.';
    }
  }

  // a local DateTime as YYYY-MM-DD text, what formatLongDate takes
  String _dateOnly(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}
