/// Minimal injectable clock.
///
/// Domain decisions that depend on "now" (work window evaluation, automatic
/// start/end, GPS freshness) take a [Clock] so tests are deterministic without
/// pulling in a time package. UI-only elapsed displays may keep using
/// `DateTime.now()`.
class Clock {
  const Clock();

  DateTime now() => DateTime.now();
}
