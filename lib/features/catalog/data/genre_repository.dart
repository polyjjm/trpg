import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/genre.dart';

/// genres 컬렉션 — 홈 탭의 장르별 진열 행 제목/순서를 여기서 읽는다.
/// lib/admin/data/genre_repository.dart와 쿼리 모양은 같지만(같은 컬렉션,
/// active==true + orderBy sortOrder), lib/features/**가 lib/admin/을
/// import할 수 없어 따로 둔 리더 쪽 사본이다.
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
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Genre.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }
}
