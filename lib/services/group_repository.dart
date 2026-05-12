import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:scheduler/models/group_summary.dart';
import 'package:scheduler/utils/invite_code.dart';

const int _maxCreatedGroups = 10;

class GroupRepository {
  GroupRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  User? get _user => _auth.currentUser;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');

  DocumentReference<Map<String, dynamic>> _groupDoc(String inviteCode) =>
      _groups.doc(inviteCode);

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _memberships(String uid) =>
      _userDoc(uid).collection('groupMemberships');

  Future<void> _ensureUserMirror() async {
    final user = _user;
    if (user == null) return;
    await _userDoc(user.uid).set({
      'email': user.email,
      'displayName': user.displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Creates [inviteCode] doc under `groups/` and membership rows (transaction).
  Future<void> createGroup({
    required String name,
    required String inviteCode,
    required String displayName,
  }) async {
    final user = _user;
    if (user == null) throw StateError('Not signed in');

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Group name required');

    final code = normalizeInviteCode(inviteCode);
    if (!isValidInviteCodeFormat(code)) {
      throw ArgumentError(
        'Invite code must be 6 characters (1–9, A–Z except O).',
      );
    }

    await _ensureUserMirror();

    final userSnap = await _userDoc(user.uid).get();
    final createdGroups =
        (userSnap.data()?['groupCount'] as num?)?.toInt() ?? 0;
    if (createdGroups >= _maxCreatedGroups) {
      throw GroupLimitReachedException(_maxCreatedGroups);
    }

    final groupRef = _groupDoc(code);
    final memberRef = groupRef.collection('members').doc(user.uid);
    final membershipRef = _memberships(user.uid).doc(code);
    final userRef = _userDoc(user.uid);

    await _db.runTransaction((txn) async {
      final g = await txn.get(groupRef);
      if (g.exists) {
        throw GroupInviteTakenException(code);
      }

      txn.set(groupRef, {
        'name': trimmedName,
        'inviteCode': code,
        'createdBy': user.uid,
        'ownerId': user.uid,
        'memberCount': 1,
        'createdAt': FieldValue.serverTimestamp(),
      });

      txn.set(memberRef, {
        'displayName': displayName.trim(),
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      txn.set(membershipRef, {
        'displayName': displayName.trim(),
        'groupName': trimmedName,
        'inviteCode': code,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      txn.set(userRef, {
        'groupCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Generates codes until [createGroup] succeeds or [maxAttempts] exhausted.
  Future<String> createGroupWithGeneratedCode({
    required String name,
    required String displayName,
    int maxAttempts = 24,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      final code = generateRandomInviteCode();
      try {
        await createGroup(
          name: name,
          inviteCode: code,
          displayName: displayName,
        );
        return code;
      } on GroupInviteTakenException {
        continue;
      }
    }
    throw StateError('Could not allocate a unique invite code; try again.');
  }

  Future<void> joinGroup(String rawCode, {required String displayName}) async {
    final user = _user;
    if (user == null) throw StateError('Not signed in');

    final code = normalizeInviteCode(rawCode);
    if (!isValidInviteCodeFormat(code)) {
      throw ArgumentError('Invalid invite code.');
    }

    await _ensureUserMirror();

    final groupRef = _groupDoc(code);
    final memberRef = groupRef.collection('members').doc(user.uid);
    final membershipRef = _memberships(user.uid).doc(code);

    await _db.runTransaction((txn) async {
      final g = await txn.get(groupRef);
      if (!g.exists) {
        throw GroupNotFoundException(code);
      }

      final m = await txn.get(memberRef);
      if (m.exists) {
        throw AlreadyMemberException(code);
      }

      final data = g.data()!;
      final groupName = data['name'] as String? ?? code;

      txn.update(groupRef, {'memberCount': FieldValue.increment(1)});

      txn.set(memberRef, {
        'displayName': displayName.trim(),
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      txn.set(membershipRef, {
        'displayName': displayName.trim(),
        'groupName': groupName,
        'inviteCode': code,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    });

    // After joining, copy user's base availability into the group's availability
    // for the current week so the user shows availability immediately.
    try {
      final userBaseDoc = await _userDoc(
        user.uid,
      ).collection('meta').doc('baseAvailability').get();
      if (userBaseDoc.exists) {
        // Compute ISO-like week id: YYYY-Www (Monday anchor)
        DateTime now = DateTime.now().toUtc();
        final weekStart = now.weekday == DateTime.sunday
            ? now
            : now.add(Duration(days: 1 - now.weekday));
        final weekNum =
            ((weekStart.difference(DateTime(weekStart.year, 1, 4)).inDays) ~/
                7) +
            1;
        final weekId =
            '${weekStart.year}-W${weekNum.toString().padLeft(2, '0')}';

        final dayChunks =
            userBaseDoc.data()?['dayChunks'] as Map<String, dynamic>? ?? {};
        final chunks = <String, List<Map<String, double>>>{};
        dayChunks.forEach((day, ranges) {
          chunks[day] = (ranges as List<dynamic>)
              .map(
                (r) => {
                  'start': ((r as Map<String, dynamic>)['start'] as num)
                      .toDouble(),
                  'end': ((r)['end'] as num).toDouble(),
                },
              )
              .toList();
        });

        final groupRef = _groupDoc(code);
        final availDoc = groupRef
            .collection('availability')
            .doc('${user.uid}_$weekId');
        await availDoc.set({
          'uid': user.uid,
          'weekId': weekId,
          'dayChunks': chunks,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // Non-fatal — ignore if base availability missing or write fails.
    }
  }

  Future<bool> leaveGroup(String rawCode) async {
    final user = _user;
    if (user == null) throw StateError('Not signed in');

    final code = normalizeInviteCode(rawCode);
    final groupRef = _groupDoc(code);
    final memberRef = groupRef.collection('members').doc(user.uid);
    final membershipRef = _memberships(user.uid).doc(code);

    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw GroupNotFoundException(code);
    }

    final memberSnap = await memberRef.get();
    if (!memberSnap.exists) {
      throw NotMemberException(code);
    }

    final groupData = groupSnap.data()!;
    final memberCount = (groupData['memberCount'] as num?)?.toInt() ?? 0;
    final ownerId = groupData['ownerId'] as String? ?? '';
    final creatorId = groupData['createdBy'] as String? ?? ownerId;

    final batch = _db.batch();

    final userAvailability = await groupRef
        .collection('availability')
        .where('uid', isEqualTo: user.uid)
        .get();
    for (final doc in userAvailability.docs) {
      batch.delete(doc.reference);
    }

    if (memberCount <= 1) {
      final allMembers = await groupRef.collection('members').get();
      for (final doc in allMembers.docs) {
        batch.delete(doc.reference);
      }

      final allAvailability = await groupRef.collection('availability').get();
      for (final doc in allAvailability.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(membershipRef);
      batch.delete(memberRef);
      batch.delete(groupRef);

      if (creatorId == user.uid) {
        batch.set(_userDoc(user.uid), {
          'groupCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
      return true;
    }

    if (ownerId == user.uid) {
      final membersSnap = await groupRef.collection('members').get();
      final replacement = membersSnap.docs.firstWhere(
        (doc) => doc.id != user.uid,
        orElse: () => throw StateError('No replacement owner available'),
      );

      batch.update(groupRef, {
        'ownerId': replacement.id,
        'memberCount': FieldValue.increment(-1),
      });
    } else {
      batch.update(groupRef, {'memberCount': FieldValue.increment(-1)});
    }

    batch.delete(membershipRef);
    batch.delete(memberRef);
    await batch.commit();
    return false;
  }

  Future<void> renameGroup({
    required String rawCode,
    required String newName,
  }) async {
    final user = _user;
    if (user == null) throw StateError('Not signed in');

    final code = normalizeInviteCode(rawCode);
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Group name required');
    }

    final groupRef = _groupDoc(code);
    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw GroupNotFoundException(code);
    }

    final data = groupSnap.data()!;
    final ownerId = data['ownerId'] as String? ?? '';
    if (ownerId != user.uid) {
      throw StateError('Only the owner can rename this group.');
    }

    await groupRef.update({
      'name': trimmedName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setGroupMeeting({
    required String rawCode,
    required DateTime start,
    required int durationMinutes,
  }) async {
    final user = _user;
    if (user == null) throw StateError('Not signed in');

    final code = normalizeInviteCode(rawCode);
    final groupRef = _groupDoc(code);
    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) throw GroupNotFoundException(code);

    final data = groupSnap.data()!;
    final ownerId = data['ownerId'] as String? ?? '';
    if (ownerId != user.uid) throw StateError('Only owner can set meeting');

    await groupRef.update({
      'meeting': {
        'start': Timestamp.fromDate(start),
        'durationMinutes': durationMinutes,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearGroupMeeting({required String rawCode}) async {
    final user = _user;
    if (user == null) throw StateError('Not signed in');

    final code = normalizeInviteCode(rawCode);
    final groupRef = _groupDoc(code);
    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) throw GroupNotFoundException(code);

    final data = groupSnap.data()!;
    final ownerId = data['ownerId'] as String? ?? '';
    if (ownerId != user.uid) throw StateError('Only owner can clear meeting');

    await groupRef.update({
      'meeting': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getGroupDoc(
    String rawCode,
  ) async {
    final code = normalizeInviteCode(rawCode);
    return _groupDoc(code).get();
  }

  Stream<List<GroupSummary>> watchMyGroups() {
    final user = _user;
    if (user == null) {
      return Stream.value([]);
    }

    return _memberships(user.uid).snapshots().asyncMap((snap) async {
      final summaries = <GroupSummary>[];
      for (final doc in snap.docs) {
        final code = doc.id;
        final membership = doc.data();
        final role = membership['role'] as String? ?? 'member';
        final nameFromMembership = membership['groupName'] as String? ?? code;

        final groupSnap = await _groupDoc(code).get();
        final memberCount = !groupSnap.exists
            ? 0
            : (groupSnap.data()?['memberCount'] as num?)?.toInt() ?? 0;

        final name = !groupSnap.exists
            ? nameFromMembership
            : (groupSnap.data()?['name'] as String? ?? nameFromMembership);

        // Read meeting if present
        Map<String, dynamic>? meeting;
        if (groupSnap.exists) {
          final raw = groupSnap.data()?['meeting'];
          if (raw is Map<String, dynamic>) meeting = raw;
        }
        DateTime? meetingStart;
        int? meetingDuration;
        if (meeting != null) {
          final ts = meeting['start'];
          if (ts is Timestamp) meetingStart = ts.toDate();
          meetingDuration = (meeting['durationMinutes'] as num?)?.toInt();
        }

        summaries.add(
          GroupSummary(
            inviteCode: code,
            name: name,
            memberCount: memberCount,
            role: role,
            meetingStart: meetingStart,
            meetingDurationMinutes: meetingDuration,
          ),
        );
      }
      summaries.sort((a, b) => a.name.compareTo(b.name));
      return summaries;
    });
  }
}

class GroupInviteTakenException implements Exception {
  GroupInviteTakenException(this.code);
  final String code;
}

class GroupNotFoundException implements Exception {
  GroupNotFoundException(this.code);
  final String code;
}

class GroupLimitReachedException implements Exception {
  GroupLimitReachedException(this.limit);
  final int limit;
}

class NotMemberException implements Exception {
  NotMemberException(this.code);
  final String code;
}

class AlreadyMemberException implements Exception {
  AlreadyMemberException(this.code);
  final String code;
}
