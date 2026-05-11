import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:scheduler/models/group_summary.dart';
import 'package:scheduler/utils/invite_code.dart';

class GroupRepository {
  GroupRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
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
    await _userDoc(user.uid).set(
      {
        'email': user.email,
        'displayName': user.displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Creates [inviteCode] doc under `groups/` and membership rows (transaction).
  Future<void> createGroup({
    required String name,
    required String inviteCode,
  }) async {
    final user = _user;
    if (user == null) throw StateError('Not signed in');

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Group name required');

    final code = normalizeInviteCode(inviteCode);
    if (!isValidInviteCodeFormat(code)) {
      throw ArgumentError('Invite code must be 6 characters (1–9, A–Z except O).');
    }

    await _ensureUserMirror();

    final groupRef = _groupDoc(code);
    final memberRef = groupRef.collection('members').doc(user.uid);
    final membershipRef = _memberships(user.uid).doc(code);

    await _db.runTransaction((txn) async {
      final g = await txn.get(groupRef);
      if (g.exists) {
        throw GroupInviteTakenException(code);
      }

      txn.set(groupRef, {
        'name': trimmedName,
        'inviteCode': code,
        'ownerId': user.uid,
        'memberCount': 1,
        'createdAt': FieldValue.serverTimestamp(),
      });

      txn.set(memberRef, {
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      txn.set(membershipRef, {
        'groupName': trimmedName,
        'inviteCode': code,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Generates codes until [createGroup] succeeds or [maxAttempts] exhausted.
  Future<String> createGroupWithGeneratedCode({
    required String name,
    int maxAttempts = 24,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      final code = generateRandomInviteCode();
      try {
        await createGroup(name: name, inviteCode: code);
        return code;
      } on GroupInviteTakenException {
        continue;
      }
    }
    throw StateError('Could not allocate a unique invite code; try again.');
  }

  Future<void> joinGroup(String rawCode) async {
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

      txn.update(groupRef, {
        'memberCount': FieldValue.increment(1),
      });

      txn.set(memberRef, {
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      txn.set(membershipRef, {
        'groupName': groupName,
        'inviteCode': code,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    });
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
        final nameFromMembership =
            membership['groupName'] as String? ?? code;

        final groupSnap = await _groupDoc(code).get();
        final memberCount = !groupSnap.exists
            ? 0
            : (groupSnap.data()?['memberCount'] as num?)?.toInt() ?? 0;

        final name = !groupSnap.exists
            ? nameFromMembership
            : (groupSnap.data()?['name'] as String? ?? nameFromMembership);

        summaries.add(
          GroupSummary(
            inviteCode: code,
            name: name,
            memberCount: memberCount,
            role: role,
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

class AlreadyMemberException implements Exception {
  AlreadyMemberException(this.code);
  final String code;
}
