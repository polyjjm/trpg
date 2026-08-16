import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/genre.dart';

/// genres 컬렉션 — 활성화된 장르만 정렬해서 보여준다(스토리팩 생성 화면의
/// 장르 선택지). 목록 자체를 편집하는 관리 UI는 아직 없고, 지금은 Firebase
/// 콘솔에서 직접 채운다(FIRESTORE_SCHEMA.md 참고).
class GenreRepository {
  GenreRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<Genre>> watchActiveGenres() {
    return _firestore
        .collection('genres')
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Genre.fromFirestore(doc.id, doc.data())).toList());
  }
}
