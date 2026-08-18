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
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Genre.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// 관리자 화면 전용 — 비활성 장르까지 전부 보여준다. 정렬 필드 하나만 쓰는
  /// orderBy라 복합 색인이 필요 없다.
  Stream<List<Genre>> watchAllGenres() {
    return _firestore
        .collection('genres')
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Genre.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> createGenre({
    required String name,
    required String slug,
    required int sortOrder,
    required bool active,
  }) async {
    await _firestore.collection('genres').add({
      'name': name,
      'slug': slug,
      'sortOrder': sortOrder,
      'active': active,
    });
  }

  /// 이름/슬러그/정렬/활성 여부를 통째로 갱신한다. 삭제는 의도적으로 없다 —
  /// 이미 이 slug를 참조하는 storyPack이 있을 수 있어서, 안 쓰게 하려면
  /// active를 false로 내리는 것만 지원한다(genres/{genreId} 문서 주석 참고).
  Future<void> updateGenre(
    String genreId, {
    required String name,
    required String slug,
    required int sortOrder,
    required bool active,
  }) async {
    await _firestore.collection('genres').doc(genreId).update({
      'name': name,
      'slug': slug,
      'sortOrder': sortOrder,
      'active': active,
    });
  }
}
