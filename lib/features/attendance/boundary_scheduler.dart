import 'dart:async';

/// Schedules the single lightweight work-window boundary check.
///
/// A concrete abstraction (instead of a raw `Timer` in the controller) so
/// tests can verify the computed delay and avoid pending timers in widget
/// tests.
abstract class BoundaryScheduler {
  void schedule(Duration delay, void Function() callback);

  void cancel();
}

/// Production scheduler backed by a one-shot [Timer].
class TimerBoundaryScheduler implements BoundaryScheduler {
  Timer? _timer;

  @override
  void schedule(Duration delay, void Function() callback) {
    cancel();
    _timer = Timer(delay, callback);
  }

  @override
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
