import 'dart:async';

/// runs jobs one at a time, even when they're started at the same moment
///
/// dart is single threaded but every await lets other code run, so two quick
/// taps on checkout can both pass the "is there enough stock" check before
/// either one writes, each thinking the stock is still untouched
///
/// every caller chains onto the tail of a queue, so job 2 can't start until job 1 is done
class Mutex {
  // the finish line of the last job handed out, null when nothing is running
  Future<void>? _tail;

  bool get isBusy => _tail != null;

  /// waits for whatever is already queued, then runs [job] and returns its result
  Future<T> run<T>(Future<T> Function() job) {
    final previous = _tail;
    // completer is a future we finish by hand, this one marks the end of our turn
    final ours = Completer<void>();
    _tail = ours.future;

    return _runAfter(previous, job, ours);
  }

  Future<T> _runAfter<T>(
    Future<void>? previous,
    Future<T> Function() job,
    Completer<void> ours,
  ) async {
    // wait our turn, a failed earlier job must not block the queue so swallow its error
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }

    try {
      return await job();
    } finally {
      // let the next job start, and clear the tail if nobody queued behind us
      if (identical(_tail, ours.future)) _tail = null;
      ours.complete();
    }
  }
}
