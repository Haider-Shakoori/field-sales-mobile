/// Shared date/time helpers for the attendance + GPS tracking layer.
///
/// New Batch 7 records store instants as UTC ISO-8601 strings (`...Z`) and the
/// work-session day bucket as the LOCAL calendar date (`yyyy-MM-dd`), because a
/// salesman's workday is defined in their local timezone.
String utcIso(DateTime time) => time.toUtc().toIso8601String();

String localDateKey(DateTime time) {
  final local = time.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime? parseStoredTime(String? value) =>
    value == null || value.isEmpty ? null : DateTime.parse(value);
