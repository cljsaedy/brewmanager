// a function that gives the current time, the stores save it as utc iso text like 2026-11-01T05:30:00.000Z
// the app uses utcNow, tests pass their own clock so the saved times are known
typedef Clock = DateTime Function();
DateTime utcNow() => DateTime.now().toUtc();
