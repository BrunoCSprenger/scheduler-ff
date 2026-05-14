import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class TimezoneService {
  TimezoneService._();

  static bool _initialized = false;

  static void _ensureLoaded() {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    _initialized = true;
  }

  static Future<void> ensureInitialized() async {
    _ensureLoaded();
  }

  static Future<String> getDeviceTimezone() async {
    await ensureInitialized();
    return _guessTimezoneFromSystem();
  }

  static List<String> allTimezoneNames() {
    _ensureLoaded();
    final names = tz.timeZoneDatabase.locations.keys.toList()..sort();
    return names;
  }

  static String formatTimezoneLabel(String timezoneName) {
    _ensureLoaded();
    try {
      final location = tz.getLocation(timezoneName);
      final now = DateTime.now().toUtc();
      final localNow = tz.TZDateTime.from(now, location);
      final offset = localNow.timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final hours = offset.inHours.abs().toString().padLeft(2, '0');
      final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      return '$timezoneName (UTC$sign$hours:$minutes)';
    } catch (_) {
      return timezoneName;
    }
  }

  static DateTime currentWeekMonday(String timezoneName) {
    _ensureLoaded();
    final now = DateTime.now().toUtc();
    return mondayFromDate(convertDateTime(now, timezoneName));
  }

  static DateTime mondayFromWeekId(String weekId) {
    final parts = weekId.split('-W');
    final year = int.parse(parts[0]);
    final week = int.parse(parts[1]);
    final jan4 = DateTime(year, 1, 4);
    final ref = jan4.subtract(Duration(days: jan4.weekday - DateTime.monday));
    return DateTime(
      ref.year,
      ref.month,
      ref.day,
    ).add(Duration(days: (week - 1) * 7));
  }

  static DateTime mondayFromDate(DateTime date) {
    final localDate = DateTime(date.year, date.month, date.day);
    return localDate.subtract(
      Duration(days: localDate.weekday - DateTime.monday),
    );
  }

  static DateTime convertDateTime(DateTime dateTime, String timezoneName) {
    _ensureLoaded();
    try {
      final location = tz.getLocation(timezoneName);
      return tz.TZDateTime.from(dateTime.toUtc(), location);
    } catch (_) {
      return dateTime.toLocal();
    }
  }

  static Map<int, List<RangeValues>> convertWeeklyAvailability({
    required Map<int, List<RangeValues>> sourceDayChunks,
    required String sourceTimezone,
    required String targetTimezone,
    required DateTime referenceMonday,
  }) {
    _ensureLoaded();
    final result = {for (var day = 0; day < 7; day++) day: <RangeValues>[]};

    if (sourceDayChunks.isEmpty) {
      return result;
    }

    try {
      final sourceLocation = tz.getLocation(sourceTimezone);
      final targetLocation = tz.getLocation(targetTimezone);
      final sourceMonday = tz.TZDateTime(
        sourceLocation,
        referenceMonday.year,
        referenceMonday.month,
        referenceMonday.day,
      );
      final targetMonday = DateTime(
        referenceMonday.year,
        referenceMonday.month,
        referenceMonday.day,
      );

      for (final entry in sourceDayChunks.entries) {
        final sourceDay = entry.key;
        final ranges = entry.value;
        for (final range in ranges) {
          final startMinutes = (range.start * 60).round();
          final endMinutes = (range.end * 60).round();
          for (var minute = startMinutes; minute < endMinutes; minute += 30) {
            final sourceMoment = sourceMonday.add(
              Duration(days: sourceDay, minutes: minute),
            );
            final targetMoment = tz.TZDateTime.from(
              sourceMoment,
              targetLocation,
            );
            final targetDate = DateTime(
              targetMoment.year,
              targetMoment.month,
              targetMoment.day,
            );
            final targetDayIndex = targetDate.difference(targetMonday).inDays;
            if (targetDayIndex < 0 || targetDayIndex >= 7) continue;

            final startHour = targetMoment.hour + (targetMoment.minute / 60.0);
            result[targetDayIndex]!.add(
              RangeValues(startHour, startHour + 0.5),
            );
          }
        }
      }
    } catch (_) {
      return sourceDayChunks;
    }

    for (final day in result.keys) {
      result[day] = _mergeRanges(result[day] ?? const <RangeValues>[]);
    }
    return result;
  }

  static List<RangeValues> _mergeRanges(List<RangeValues> ranges) {
    if (ranges.isEmpty) return const [];
    final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
    final merged = <RangeValues>[];
    var current = sorted.first;
    for (final next in sorted.skip(1)) {
      if (next.start <= current.end + 0.0001) {
        current = RangeValues(
          current.start,
          next.end > current.end ? next.end : current.end,
        );
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);
    return merged;
  }

  static String _guessTimezoneFromSystem() {
    final offset = DateTime.now().timeZoneOffset;
    final nowUtc = DateTime.now().toUtc();
    final matches = tz.timeZoneDatabase.locations.values.where((location) {
      final localNow = tz.TZDateTime.from(nowUtc, location);
      return localNow.timeZoneOffset == offset;
    }).toList();

    if (matches.isEmpty) {
      return 'UTC';
    }

    final preferredNames = [
      'Etc/UTC',
      'Europe/London',
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Los_Angeles',
    ];
    for (final preferred in preferredNames) {
      if (matches.any((location) => location.name == preferred)) {
        return preferred;
      }
    }

    return matches.first.name;
  }
}
