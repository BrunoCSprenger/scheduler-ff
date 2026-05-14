import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:scheduler/services/timezone_service.dart';

class AvailabilityService {
  AvailabilityService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  User? get _user => _auth.currentUser;

  Future<void> _ensureUserMirror() async {
    final user = _user;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).set({
      'email': user.email,
      'displayName': user.displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Save availability for current user in a group for a specific week.
  /// [dayChunks] maps day index (0-6) to multiple availability ranges.
  /// [weekId] format: "2026-W19" (ISO week) or "2026-05-05" (Monday anchor)
  Future<void> saveAvailability({
    required String inviteCode,
    required String weekId,
    required Map<int, List<RangeValues>> dayChunks,
  }) async {
    final user = _user;
    if (user == null) throw StateError('Not signed in');
    final timezone = await getCurrentUserTimezone();

    final chunks = <String, List<Map<String, double>>>{};
    dayChunks.forEach((day, ranges) {
      chunks[day.toString()] = ranges
          .map((range) => {'start': range.start, 'end': range.end})
          .toList();
    });

    final docRef = _db
        .collection('groups')
        .doc(inviteCode)
        .collection('availability')
        .doc('${user.uid}_$weekId');

    await docRef.set({
      'uid': user.uid,
      'weekId': weekId,
      'timezone': timezone,
      'dayChunks': chunks,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Get availability for all members in a group for a specific week.
  /// Returns Map<uid, Map<day, List<RangeValues>>>
  Stream<Map<String, Map<int, List<RangeValues>>>> watchGroupAvailability({
    required String inviteCode,
    required String weekId,
    required String viewerTimezone,
  }) {
    // Watch per-week availability and, when the current user has no explicit
    // per-week entry, merge in their base availability so it applies to every
    // week identically (no per-week selection required).
    return _db
        .collection('groups')
        .doc(inviteCode)
        .collection('availability')
        .where('weekId', isEqualTo: weekId)
        .snapshots()
        .asyncMap((snapshot) async {
          final rawResult = <String, Map<int, List<RangeValues>>>{};
          final sourceTimezones = <String, String>{};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final uid = data['uid'] as String? ?? doc.id.split('_').first;
            final docTimezone = (data['timezone'] as String?)?.trim();
            sourceTimezones[uid] =
                (docTimezone != null && docTimezone.isNotEmpty)
                ? docTimezone
                : (uid == _user?.uid ? await getCurrentUserTimezone() : 'UTC');
            final dayChunksMap =
                data['dayChunks'] as Map<String, dynamic>? ?? {};
            final dayChunks = <int, List<RangeValues>>{};

            if (dayChunksMap.isNotEmpty) {
              dayChunksMap.forEach((dayStr, chunks) {
                final day = int.parse(dayStr);
                final ranges = <RangeValues>[];
                for (final chunk in (chunks as List<dynamic>? ?? const [])) {
                  final start = (chunk as Map<String, dynamic>)['start'];
                  final end = chunk['end'];
                  ranges.add(
                    RangeValues(
                      (start as num).toDouble(),
                      (end as num).toDouble(),
                    ),
                  );
                }
                dayChunks[day] = ranges;
              });
            } else {
              final legacyDays = data['availableDays'] as List<dynamic>?;
              final legacyHours = data['dayHours'] as Map<String, dynamic>?;
              if (legacyHours != null && legacyHours.isNotEmpty) {
                legacyHours.forEach((dayStr, hours) {
                  final day = int.parse(dayStr);
                  final hoursList = (hours as List?)?.cast<int>() ?? [];
                  dayChunks[day] = _hoursToRanges(hoursList);
                });
              } else if (legacyDays != null) {
                for (final value in legacyDays) {
                  final day = value as int;
                  dayChunks[day] = const [RangeValues(0, 24)];
                }
              }
            }

            rawResult[uid] = dayChunks;
          }

          // If the current user has no per-week availability in this group, try
          // to merge their base availability from `users/{uid}/meta/baseAvailability`.
          final user = _user;
          if (user != null && !rawResult.containsKey(user.uid)) {
            final baseDoc = await _db
                .collection('users')
                .doc(user.uid)
                .collection('meta')
                .doc('baseAvailability')
                .get();
            if (baseDoc.exists) {
              final data = baseDoc.data() ?? {};
              final baseTimezone = (data['timezone'] as String?)?.trim();
              sourceTimezones[user.uid] =
                  (baseTimezone != null && baseTimezone.isNotEmpty)
                  ? baseTimezone
                  : await getCurrentUserTimezone();
              final dayChunksMap =
                  data['dayChunks'] as Map<String, dynamic>? ?? {};
              final dayChunks = <int, List<RangeValues>>{};
              dayChunksMap.forEach((dayStr, chunks) {
                final day = int.parse(dayStr);
                final ranges = <RangeValues>[];
                for (final chunk in (chunks as List<dynamic>? ?? const [])) {
                  final start = (chunk as Map<String, dynamic>)['start'];
                  final end = chunk['end'];
                  ranges.add(
                    RangeValues(
                      (start as num).toDouble(),
                      (end as num).toDouble(),
                    ),
                  );
                }
                dayChunks[day] = ranges;
              });
              rawResult[user.uid] = dayChunks;
            }
          }

          final referenceMonday = TimezoneService.mondayFromWeekId(weekId);
          final converted = <String, Map<int, List<RangeValues>>>{};
          for (final entry in rawResult.entries) {
            final uid = entry.key;
            final sourceTimezone = sourceTimezones[uid] ?? 'UTC';
            converted[uid] = TimezoneService.convertWeeklyAvailability(
              sourceDayChunks: entry.value,
              sourceTimezone: sourceTimezone,
              targetTimezone: viewerTimezone,
              referenceMonday: referenceMonday,
            );
          }
          return converted;
        });
  }

  /// Save the user's base (global) availability that should apply to all groups.
  /// Stores under `users/{uid}/baseAvailability` with the same `dayChunks` shape.
  Future<void> saveBaseAvailability({
    required Map<int, List<RangeValues>> dayChunks,
  }) async {
    final user = _user;
    if (user == null) throw StateError('Not signed in');
    // Ensure a minimal user mirror exists; many rules require the user's
    // document to be present or writable only by its owner. This is a
    // non-destructive merge that should satisfy such rules.
    try {
      await _db.collection('users').doc(user.uid).set({
        'email': user.email,
        'displayName': user.displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignore — if this write is blocked by rules the subsequent write
      // will also fail, returning the original permission error.
    }

    final chunks = <String, List<Map<String, double>>>{};
    dayChunks.forEach((day, ranges) {
      chunks[day.toString()] = ranges
          .map((range) => {'start': range.start, 'end': range.end})
          .toList();
    });
    final timezone = await getCurrentUserTimezone();

    final docRef = _db
        .collection('users')
        .doc(user.uid)
        .collection('meta')
        .doc('baseAvailability');
    await docRef.set({
      'timezone': timezone,
      'dayChunks': chunks,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveUserTimezone(String timezone) async {
    final user = _user;
    if (user == null) throw StateError('Not signed in');

    await _ensureUserMirror();
    await _db
        .collection('users')
        .doc(user.uid)
        .collection('meta')
        .doc('settings')
        .set({
          'timezone': timezone,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Stream<String> watchCurrentUserTimezone() {
    final user = _user;
    if (user == null) return Stream.value('UTC');

    return _db
        .collection('users')
        .doc(user.uid)
        .collection('meta')
        .doc('settings')
        .snapshots()
        .asyncMap((snap) async {
          final timezone = snap.data()?['timezone'] as String?;
          if (timezone != null && timezone.trim().isNotEmpty) {
            return timezone.trim();
          }
          return TimezoneService.getDeviceTimezone();
        });
  }

  Future<String> getCurrentUserTimezone() async {
    final user = _user;
    if (user == null) return TimezoneService.getDeviceTimezone();
    final doc = await _db
        .collection('users')
        .doc(user.uid)
        .collection('meta')
        .doc('settings')
        .get();
    final timezone = doc.data()?['timezone'] as String?;
    if (timezone != null && timezone.trim().isNotEmpty) {
      return timezone.trim();
    }
    return TimezoneService.getDeviceTimezone();
  }

  /// Watch the current user's base availability.
  Stream<Map<int, List<RangeValues>>> watchBaseAvailability() {
    final user = _user;
    if (user == null) return Stream.value(const <int, List<RangeValues>>{});

    final docRef = _db
        .collection('users')
        .doc(user.uid)
        .collection('meta')
        .doc('baseAvailability');
    return docRef.snapshots().map((snap) {
      final data = snap.data() ?? {};
      final dayChunksMap = data['dayChunks'] as Map<String, dynamic>? ?? {};
      final dayChunks = <int, List<RangeValues>>{};
      dayChunksMap.forEach((dayStr, chunks) {
        final day = int.parse(dayStr);
        final ranges = <RangeValues>[];
        for (final chunk in (chunks as List<dynamic>? ?? const [])) {
          final start = (chunk as Map<String, dynamic>)['start'];
          final end = chunk['end'];
          ranges.add(
            RangeValues((start as num).toDouble(), (end as num).toDouble()),
          );
        }
        dayChunks[day] = ranges;
      });
      return dayChunks;
    });
  }

  List<RangeValues> _hoursToRanges(List<int> hoursList) {
    if (hoursList.isEmpty) return const [];

    final sorted = hoursList.toSet().toList()..sort();
    final ranges = <RangeValues>[];
    var start = sorted.first;
    var previous = sorted.first;

    for (final hour in sorted.skip(1)) {
      if (hour == previous + 1) {
        previous = hour;
        continue;
      }

      ranges.add(RangeValues(start.toDouble(), (previous + 1).toDouble()));
      start = hour;
      previous = hour;
    }

    ranges.add(RangeValues(start.toDouble(), (previous + 1).toDouble()));
    return ranges;
  }

  /// Get members in a group with their display names.
  Stream<List<GroupMember>> watchGroupMembers({required String inviteCode}) {
    return _db
        .collection('groups')
        .doc(inviteCode)
        .collection('members')
        .snapshots()
        .asyncMap((snapshot) async {
          final members = <GroupMember>[];
          for (final doc in snapshot.docs) {
            final uid = doc.id;
            final data = doc.data();
            final displayName =
                (data['displayName'] as String?)?.trim().isNotEmpty == true
                ? (data['displayName'] as String).trim()
                : uid;
            final role = (data['role'] as String?)?.trim().isNotEmpty == true
                ? (data['role'] as String).trim()
                : 'member';
            members.add(
              GroupMember(uid: uid, displayName: displayName, role: role),
            );
          }
          members.sort((a, b) => a.displayName.compareTo(b.displayName));
          return members;
        });
  }
}

class GroupMember {
  const GroupMember({
    required this.uid,
    required this.displayName,
    required this.role,
  });

  final String uid;
  final String displayName;
  final String role;
}
