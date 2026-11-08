import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/count_line.dart';
import '../data/count_store.dart';
import '../data/stock_item.dart';
import '../data/submit_store.dart';
import '../logic/business_day.dart';
import '../logic/count_math.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import '../theme/app_theme.dart';
import 'submit_widgets.dart';

// the 3 steps of a submit
enum _Step { review, date, done }

// the barista's submit: review the day, confirm the date, then see it was submitted (rule 4 and 5)
// no expected numbers anywhere here, they stay in the owner section
class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key, required this.store});

  final CountStore store;

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  _Step _step = _Step.review;

  // both null while loading
  DraftDay? _draft;
  DayReview? _review;

  // the date to submit, starts on the draft's own date
  late String _chosenDate;
  // the answer to "was the cafe open on those days?", only used when the date moved
  bool _skippedDaysOpen = true;

  // true while saving, the submit button is off so a double tap does nothing
  bool _submitting = false;
  // restock recommended items, filled once submitted
  List<String> _restockItems = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // loadDraft again so the review shows what is saved right now
  Future<void> _load() async {
    final draft = await widget.store.loadDraft();
    final review = await widget.store.submits.review(draft);
    // mounted = this screen is still open
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _review = review;
      _chosenDate = draft.day.businessDate;
    });
  }

  String get _draftDate => _draft!.day.businessDate;

  // the dates passed over by the chosen date, empty when the date didnt move
  List<String> get _skipped {
    return skippedDates(draftDate: _draftDate, chosenDate: _chosenDate);
  }

  // the date can only go forward, and only up to today on the tablet
  // a count is for a day that already happened, so a future date is not offered
  bool get _canChangeDate => daysBetween(_draftDate, widget.store.today) > 0;

  // change date tapped: pick a date, then ask about the days it passes over
  Future<void> _changeDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_chosenDate),
      firstDate: DateTime.parse(_draftDate),
      lastDate: DateTime.parse(widget.store.today),
    );
    if (picked == null || !mounted) return;

    final date = dateText(picked);
    final passed = skippedDates(draftDate: _draftDate, chosenDate: date);
    var isOpen = true;
    if (passed.isNotEmpty) {
      final answer = await _askIfOpen(passed);
      // cancelled, so the date stays as it was
      if (answer == null) return;
      isOpen = answer;
    }

    setState(() {
      _chosenDate = date;
      _skippedDaysOpen = isOpen;
    });
  }

  // true = open, false = closed, null = cancelled
  Future<bool?> _askIfOpen(List<String> dates) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Was the cafe open on those days?'),
        content: Text(
          '${dates.map(formatShortDate).join(', ')}\n\n'
          'Yes: this count covers those days too.\n'
          'No: those days are saved as closed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No, closed'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, open'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final dayId = _draft!.day.id;
    final store = widget.store.submits;
    try {
      await store.submit(
        dayId,
        date: _chosenDate,
        skippedDaysOpen: _skippedDaysOpen,
      );
      // the day is submitted and its email is queued with the template summary,
      // now try the ai one, it never throws and keeps the template if anything goes wrong
      await widget.store.aiSummary.improve(dayId);
      final restock = await store.restockItems(dayId);
      if (!mounted) return;
      setState(() {
        _restockItems = restock;
        _step = _Step.done;
      });
    } catch (_) {
      // the transaction undid everything, so it is safe to try again
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not submit. Nothing was saved. Try again.'),
        ),
      );
    }
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: review == null
              ? const Center(child: CircularProgressIndicator())
              : switch (_step) {
                  _Step.review => _reviewStep(review),
                  _Step.date => _dateStep(),
                  _Step.done => _doneStep(),
                },
        ),
      ),
    );
  }

  // the header on top with the step's content filling the rest
  Widget _frame({required SubmitHeader header, required Widget body}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 12),
        Expanded(child: body),
      ],
    );
  }

  // step 1: the numbers on top, the lists below, warnings never stop the next step
  Widget _reviewStep(DayReview review) {
    return _frame(
      header: SubmitHeader(
        title: 'Review the day',
        subtitle: formatLongDate(_draftDate),
        stepIndex: 0,
        actions: [
          OutlinedButton(onPressed: _close, child: const Text('Back to count')),
          FilledButton(
            onPressed: () => setState(() => _step = _Step.date),
            child: const Text('Next'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statRow(review),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _eventsCard(review)),
                const SizedBox(width: 12),
                Expanded(child: _checkCard(review)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(DayReview review) {
    final toCheck =
        review.doubleCheckItems.length +
        review.openingItems.length +
        review.noRecipeItems.length;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Items changed',
            value: '${review.itemsChanged}',
            icon: Icons.edit_note,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: 'Tally total',
            value: '${review.tallyTotal}',
            icon: Icons.receipt_long_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: 'IN and OUT',
            value: '${review.events.length}',
            icon: Icons.swap_vert,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: 'To check',
            value: '$toCheck',
            icon: toCheck > 0
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            color: toCheck > 0 ? AppColors.warnText : AppColors.okText,
            background: toCheck > 0 ? AppColors.warnBg : AppColors.okBg,
          ),
        ),
      ],
    );
  }

  Widget _eventsCard(DayReview review) {
    return SectionCard(
      title: 'Restocks and finished',
      children: [
        if (review.events.isEmpty) const EmptyLine('No IN or OUT today'),
        for (final event in review.events) _eventRow(event),
      ],
    );
  }

  // a restock is green, a finished container is brown
  Widget _eventRow(ReviewEvent event) {
    final item = event.item;
    return SubmitRow(
      icon: event.isRestock ? Icons.add : Icons.check,
      color: event.isRestock ? AppColors.okText : AppColors.espresso,
      background: event.isRestock ? AppColors.okBg : AppColors.cream,
      title: item.name,
      detail: event.isRestock
          ? '+${_restockText(item, event.qty)}'
          : '${capitalized(item.containerName)} finished',
      trailing: formatTime(event.time),
    );
  }

  String _restockText(StockItem item, double qty) {
    if (item.countType == CountType.container) {
      final containers = containersIn(qty, item.containerSize!);
      return formatContainers(containers.toDouble(), item.containerName);
    }
    return amountText(item, qty);
  }

  Widget _checkCard(DayReview review) {
    final hasNotes = review.dayNote != null || review.notes.isNotEmpty;

    return SectionCard(
      title: 'Please check',
      children: [
        if (!review.hasWarnings)
          const EmptyLine('Nothing to check', icon: Icons.check_circle_outline),
        ..._warning('Used today, not counted yet', review.doubleCheckItems),
        ..._warning('Opening count, not counted yet', review.openingItems),
        ..._warning('No recipe yet', review.noRecipeItems),
        const ListTitle('Notes'),
        if (!hasNotes) const EmptyLine('No notes'),
        if (review.dayNote != null) _noteRow('Day note', review.dayNote!),
        for (final note in review.notes) _noteRow(note.itemName, note.note),
      ],
    );
  }

  // one warning with its names, nothing when the list is empty
  List<Widget> _warning(String title, List<String> names) {
    if (names.isEmpty) return const [];
    return [
      SubmitRow(
        icon: Icons.warning_amber_rounded,
        color: AppColors.warnText,
        background: AppColors.warnBg,
        title: title,
        detail: names.join(', '),
      ),
    ];
  }

  Widget _noteRow(String title, String note) {
    return SubmitRow(
      icon: Icons.sticky_note_2_outlined,
      color: AppColors.espresso,
      background: AppColors.cream,
      title: title,
      detail: note,
    );
  }

  // step 2: the date shown big, so the wrong day doesnt get submitted by accident
  Widget _dateStep() {
    final warning = skippedDayWarning(
      draftDate: _chosenDate,
      today: widget.store.today,
    );
    final date = DateTime.parse(_chosenDate);

    return _frame(
      header: SubmitHeader(
        title: 'Confirm the date',
        subtitle: 'Submitting locks this day',
        stepIndex: 1,
        actions: [
          OutlinedButton(
            onPressed: _submitting
                ? null
                : () => setState(() => _step = _Step.review),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: const Text('Submit'),
          ),
        ],
      ),
      body: Center(
        // scrolls in case a warning and the hint dont fit the short screen
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SubmitCard(
              padding: 24,
              child: Row(
                children: [
                  CalendarTile(
                    month: DateFormat('MMM').format(date),
                    day: DateFormat('d').format(date),
                    weekday: DateFormat('EEEE').format(date),
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: _dateDetails(warning)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateDetails(String? warning) {
    final skipped = _skipped;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Submit count for ${formatLongDate(_chosenDate)}?',
          style: const TextStyle(
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        if (warning != null) ...[
          const SizedBox(height: 12),
          WarningBanner(warning),
        ],
        if (skipped.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _skippedDaysOpen
                ? 'Covers ${formatCovers(_draftDate, _chosenDate)}'
                : 'Closed: ${skipped.map(formatShortDate).join(', ')}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _canChangeDate ? _changeDate : null,
          icon: const Icon(Icons.calendar_today, size: 18),
          label: const Text('Change date'),
        ),
        if (!_canChangeDate) ...[
          const SizedBox(height: 6),
          Text(
            'The date can only move forward, up to today.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  // step 3: done on the left, the restock list on the right, the email status comes in feature 9
  Widget _doneStep() {
    return _frame(
      header: SubmitHeader(
        title: 'Day submitted',
        subtitle: formatLongDate(_chosenDate),
        stepIndex: 2,
        actions: [
          FilledButton(
            onPressed: _close,
            child: const Text("Open next day's draft"),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _doneCard()),
          const SizedBox(width: 12),
          Expanded(child: _restockCard()),
        ],
      ),
    );
  }

  Widget _doneCard() {
    final text = Theme.of(context).textTheme;

    return SubmitCard(
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconTile(
                icon: Icons.check,
                color: AppColors.okText,
                background: AppColors.okBg,
                size: 64,
              ),
              const SizedBox(height: 14),
              Text(
                'Submitted ${formatLongDate(_chosenDate)}',
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Owner email comes in Feature 9.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _restockCard() {
    return SectionCard(
      title: 'Restock recommended',
      children: [
        if (_restockItems.isEmpty)
          const EmptyLine(
            'No items need restocking',
            icon: Icons.check_circle_outline,
          ),
        for (final name in _restockItems)
          SubmitRow(
            icon: Icons.shopping_basket_outlined,
            color: AppColors.warnText,
            background: AppColors.warnBg,
            title: name,
          ),
      ],
    );
  }
}
