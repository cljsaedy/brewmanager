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
import '../widgets/status_chip.dart';

// the 3 steps of a submit
enum _Step { review, date, done }

// a date with its weekday, like "Fri, Oct 30"
String _longDate(String date) {
  return DateFormat('EEE, MMM d').format(DateTime.parse(date));
}

// a date without its weekday, like "Oct 30"
String _shortDate(String date) {
  return DateFormat('MMM d').format(DateTime.parse(date));
}

// the dates a count covers, like "Oct 29–30" or "Oct 31–Nov 2" over the end of a month
String _coversText(String from, String to) {
  final sameMonth = from.substring(0, 7) == to.substring(0, 7);
  final end = sameMonth
      ? DateFormat('d').format(DateTime.parse(to))
      : _shortDate(to);
  return '${_shortDate(from)}–$end';
}

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
          '${dates.map(_shortDate).join(', ')}\n\n'
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
          padding: const EdgeInsets.all(16),
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

  // step 1: the day's summary, warnings never stop the next step
  Widget _reviewStep(DayReview review) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review ${_longDate(_draftDate)}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _summaryCard(review)),
              const SizedBox(width: 12),
              Expanded(child: _notesCard(review)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: _close,
              child: const Text('Back to count'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => setState(() => _step = _Step.date),
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.divider),
      ),
      // scrolls on its own so a long list never pushes the buttons away
      child: ListView(padding: const EdgeInsets.all(16), children: children),
    );
  }

  Widget _heading(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _line(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text),
    );
  }

  Widget _summaryCard(DayReview review) {
    return _card([
      _heading('The day'),
      _line('Items changed: ${review.itemsChanged}'),
      _line('Tally total: ${review.tallyTotal}'),
      const SizedBox(height: 12),
      _heading('IN and OUT'),
      if (review.events.isEmpty) _line('No IN or OUT today'),
      for (final event in review.events) _line(_eventText(event)),
    ]);
  }

  // like "Caramel syrup: +2 bottles · 2:15pm" or "Caramel syrup: Bottle finished · 4:30pm"
  String _eventText(ReviewEvent event) {
    final item = event.item;
    final what = event.isRestock
        ? '+${_restockText(item, event.qty)}'
        : '${capitalized(item.containerName)} finished';
    return '${item.name}: $what · ${formatTime(event.time)}';
  }

  String _restockText(StockItem item, double qty) {
    if (item.countType == CountType.container) {
      final containers = containersIn(qty, item.containerSize!);
      return formatContainers(containers.toDouble(), item.containerName);
    }
    return formatWithUnit(qty, item.baseUnit.name);
  }

  Widget _notesCard(DayReview review) {
    return _card([
      _heading('Please check'),
      if (!review.hasWarnings) _line('Nothing to check'),
      ..._warning('Used today, not counted yet', review.doubleCheckItems),
      ..._warning('Opening count, not counted yet', review.openingItems),
      ..._warning('No recipe yet', review.noRecipeItems),
      const SizedBox(height: 12),
      _heading('Notes'),
      if (review.notes.isEmpty && review.dayNote == null) _line('No notes'),
      if (review.dayNote != null) _line('Day note: ${review.dayNote}'),
      for (final note in review.notes) _line('${note.itemName}: ${note.note}'),
    ]);
  }

  // one warning with its names, nothing when the list is empty
  List<Widget> _warning(String title, List<String> names) {
    if (names.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: StatusChip(label: title, tone: ChipTone.warn),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(names.join(', ')),
      ),
    ];
  }

  // step 2: the date shown big, so the wrong day doesnt get submitted by accident
  Widget _dateStep() {
    final warning = skippedDayWarning(
      draftDate: _chosenDate,
      today: widget.store.today,
    );
    final skipped = _skipped;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Text(
                    'Submit count for ${_longDate(_chosenDate)}?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (warning != null) ...[
                    const SizedBox(height: 12),
                    StatusChip(label: warning, tone: ChipTone.warn),
                  ],
                  if (skipped.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _skippedDaysOpen
                          ? 'Covers ${_coversText(_draftDate, _chosenDate)}'
                          : 'Closed: ${skipped.map(_shortDate).join(', ')}',
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
                    const Text(
                      'The date can only move forward, up to today.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() => _step = _Step.review),
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: const Text('Submit'),
            ),
          ],
        ),
      ],
    );
  }

  // step 3: done, with the restock list, the email status comes in feature 9
  Widget _doneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: AppColors.okText,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Submitted ${_longDate(_chosenDate)}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Owner email comes in Feature 9.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  if (_restockItems.isEmpty)
                    const Text('No items need restocking')
                  else ...[
                    const StatusChip(
                      label: 'Restock recommended',
                      tone: ChipTone.warn,
                    ),
                    const SizedBox(height: 8),
                    Text(_restockItems.join(', '), textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: _close,
              child: const Text("Open next day's draft"),
            ),
          ],
        ),
      ],
    );
  }
}
