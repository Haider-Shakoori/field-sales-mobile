/// Shared date/time helpers for the attendance + GPS tracking layer.
///
/// New Batch 7 records store instants as UTC ISO-8601 strings (`...Z`) and the
/// work-session day bucket as a calendar date (`yyyy-MM-dd`), because a
/// salesman's workday is defined in the company's tenant timezone.
String utcIso(DateTime time) => time.toUtc().toIso8601String();

/// `yyyy-MM-dd` from the wall-clock fields of [time] as-is, with no timezone
/// conversion. Pass a tenant-zone wall clock (e.g. `TZDateTime`) to get the
/// tenant-local work date.
String dateKeyOf(DateTime time) {
  final year = time.year.toString().padLeft(4, '0');
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String localDateKey(DateTime time) => dateKeyOf(time.toLocal());

DateTime? parseStoredTime(String? value) =>
    value == null || value.isEmpty ? null : DateTime.parse(value);
