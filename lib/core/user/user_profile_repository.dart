import 'package:cloud_firestore/cloud_firestore.dart';

import 'author_application_status.dart';
import 'user_profile.dart';
import 'user_role.dart';

/// users/{uid} 문서를 다루는 저장소. 게임 앱과 작가 편집기가 공통으로 쓴다.
class UserProfileRepository {
  UserProfileRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('users').doc(uid);

  Future<UserProfile?> fetchProfile(String uid) async {
    final snapshot = await _doc(uid).get();
    final data = snapshot.data();
    if (data == null) return null;
    return UserProfile.fromFirestore(uid, data);
  }

  Stream<UserProfile?> watchProfile(String uid) {
    return _doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return UserProfile.fromFirestore(uid, data);
    });
  }

  /// 최초 로그인 시 문서가 없으면 role: reader인 기본 프로필로 새로 만든다.
  /// 이미 있으면 그대로 반환한다 — 기존 role/authorApplicationStatus를 덮어쓰지 않는다.
  Future<UserProfile> ensureProfile({
    required String uid,
    String? displayName,
    String? email,
  }) async {
    final existing = await fetchProfile(uid);
    if (existing != null) return existing;

    final profile = UserProfile(
      uid: uid,
      displayName: displayName ?? '',
      email: email ?? '',
      role: UserRole.reader,
      authorApplicationStatus: AuthorApplicationStatus.none,
    );

    await _doc(uid).set({
      ...profile.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return profile;
  }
}
