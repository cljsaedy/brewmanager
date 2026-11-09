// the owner section locks when the app goes to the background (rule 11)
// but android's own save and open screens (back up, restore) also put the app in the background,
// so without this the owner section locked itself while the owner was picking a backup file
// and the restore stopped quietly (found on the tablet)
// while the app's own file screen is open, the lock waits
class OwnerLock {
  OwnerLock._();

  // how many of the app's own file screens are open right now, 0 = lock normally
  static int _paused = 0;

  // true while a file screen opened by the app is showing
  static bool get isPaused => _paused > 0;

  // runs the file screen with the lock on hold, it is back on after, even when it fails
  static Future<T> pauseWhile<T>(Future<T> Function() action) async {
    _paused++;
    try {
      return await action();
    } finally {
      _paused--;
    }
  }
}
