// Time helpers. Sites use a fixed UTC offset (Pakistan has no daylight saving), so the
// same code gives the same answer on a phone in Sadiqabad and a laptop anywhere else.
import 'models.dart';

const Map<String, int> _tzOffsetMinutes = {'Asia/Karachi': 300};

class SiteClock {
  SiteClock(this.site);
  final Site site;

  int get offsetMinutes => _tzOffsetMinutes[site.timezone] ?? 300;

  /// Current time expressed in site-local wall-clock terms (as a UTC DateTime shifted by the offset).
  DateTime nowLocal() => DateTime.now().toUtc().add(Duration(minutes: offsetMinutes));

  /// "YYYY-MM-DD" for a site-local time.
  String dateKey(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';

  String todayKey() => dateKey(nowLocal());

  /// A site-local wall-clock time ("HH:mm" on dateKey) as a real instant.
  DateTime instant(String date, String hhmm) {
    final d = date.split('-').map(int.parse).toList();
    final t = hhmm.split(':').map(int.parse).toList();
    return DateTime.utc(d[0], d[1], d[2], t[0], t[1]).subtract(Duration(minutes: offsetMinutes));
  }

  /// Site-local wall clock for an instant.
  DateTime toLocal(DateTime instant) => instant.toUtc().add(Duration(minutes: offsetMinutes));

  String hhmm(DateTime instant) {
    final l = toLocal(instant);
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  /// Upcoming windows from now: the one running (or next) first, then the following ones,
  /// crossing into the next day as needed. Each item is (dateKey, window).
  List<WindowSlot> upcoming({int count = 4}) {
    final windows = site.windows.where((w) => w.active).toList()..sort((a, b) => a.order.compareTo(b.order));
    if (windows.isEmpty) return const [];
    final now = DateTime.now().toUtc();
    final out = <WindowSlot>[];
    var day = nowLocal();
    for (var i = 0; i < 4 && out.length < count; i++) {
      final key = dateKey(day);
      for (final w in windows) {
        final end = instant(key, w.end);
        if (end.isAfter(now)) out.add(WindowSlot(key, w, this));
        if (out.length >= count) break;
      }
      day = day.add(const Duration(days: 1));
    }
    return out;
  }

  WindowSlot? current() {
    final u = upcoming(count: 1);
    return u.isEmpty ? null : u.first;
  }
}

class WindowSlot {
  const WindowSlot(this.date, this.window, this.clock);
  final String date;
  final CommuteWindow window;
  final SiteClock clock;

  DateTime get startAt => clock.instant(date, window.start);
  DateTime get endAt => clock.instant(date, window.end);
  bool get isRunning {
    final n = DateTime.now().toUtc();
    return !n.isBefore(startAt) && n.isBefore(endAt);
  }

  bool get isToday => date == clock.todayKey();

  String get dayLabel {
    final today = clock.nowLocal();
    final tomorrow = today.add(const Duration(days: 1));
    if (date == clock.dateKey(today)) return 'Today';
    if (date == clock.dateKey(tomorrow)) return 'Tomorrow';
    final d = date.split('-').map(int.parse).toList();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[DateTime(d[0], d[1], d[2]).weekday - 1]} ${d[2]}/${d[1]}';
  }

  String get label => '$dayLabel · ${window.name} ${window.start}–${window.end}';

  /// Departure choices in 5-minute steps from 15 min before the window start to its end.
  List<DateTime> departureChoices() {
    final out = <DateTime>[];
    var t = startAt.subtract(const Duration(minutes: 15));
    final now = DateTime.now().toUtc();
    while (!t.isAfter(endAt)) {
      if (t.isAfter(now.subtract(const Duration(minutes: 5)))) out.add(t);
      t = t.add(const Duration(minutes: 5));
    }
    return out;
  }

  @override
  bool operator ==(Object other) => other is WindowSlot && other.date == date && other.window.id == window.id;
  @override
  int get hashCode => Object.hash(date, window.id);
}

String prettyDate(String key) {
  final d = key.split('-').map(int.parse).toList();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final dt = DateTime(d[0], d[1], d[2]);
  return '${days[dt.weekday - 1]} ${d[2]} ${months[d[1] - 1]}';
}

String minutesAgo(DateTime? at) {
  if (at == null) return '';
  final m = DateTime.now().difference(at).inMinutes;
  if (m < 1) return 'just now';
  return '$m min ago';
}
