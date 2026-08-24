import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/home_banner.dart';

/// homeBanners 컬렉션(색인) + Firebase Storage(실제 배너 이미지)를 함께
/// 다루는 저장소 — AdminImageRepository/AdminSfxRepository와 같은 구조다.
/// "홈 배너 관리" 섹션(HomeBannerManagementSection)의 CRUD + 드래그 재정렬을
/// 담당한다. genres처럼 정렬 필드 하나만 쓰는 orderBy라 복합 색인이 필요 없다.
class HomeBannerRepository {
  HomeBannerRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _banners =>
      _firestore.collection('homeBanners');

  Stream<List<AdminHomeBanner>> watchAllBanners() {
    return _banners
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminHomeBanner.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// 홈 배너는 독자 카탈로그에서 로그인 여부와 상관없이 보여야 하는 공개
  /// 자산이므로 private/admin 경로가 아니라 public/home_banners에 저장한다.
  Future<void> createBanner({
    required Uint8List imageBytes,
    required String? linkedPackId,
    required int sortOrder,
    required bool active,
    required DateTime? startAt,
    required DateTime? endAt,
    String? eyebrow,
    String? title,
    String? subtitle,
  }) async {
    final doc = _banners.doc();
    final storagePath = 'public/home_banners/${doc.id}.jpg';
    final ref = _storage.ref(storagePath);
    await ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
    final imageUrl = await ref.getDownloadURL();

    await doc.set({
      'imageUrl': imageUrl,
      'storagePath': storagePath,
      'linkedPackId': linkedPackId,
      'sortOrder': sortOrder,
      'active': active,
      'startAt': startAt != null ? Timestamp.fromDate(startAt) : null,
      'endAt': endAt != null ? Timestamp.fromDate(endAt) : null,
      'eyebrow': eyebrow,
      'title': title,
      'subtitle': subtitle,
    });
  }

  Future<void> updateBanner(
    String bannerId, {
    Uint8List? imageBytes,
    required String? linkedPackId,
    required int sortOrder,
    required bool active,
    required DateTime? startAt,
    required DateTime? endAt,
    String? eyebrow,
    String? title,
    String? subtitle,
  }) async {
    final updates = <String, dynamic>{
      'linkedPackId': linkedPackId,
      'sortOrder': sortOrder,
      'active': active,
      'startAt': startAt != null ? Timestamp.fromDate(startAt) : null,
      'endAt': endAt != null ? Timestamp.fromDate(endAt) : null,
      'eyebrow': eyebrow,
      'title': title,
      'subtitle': subtitle,
    };

    if (imageBytes != null) {
      final storagePath = 'public/home_banners/$bannerId.jpg';
      final ref = _storage.ref(storagePath);
      await ref.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      updates['imageUrl'] = await ref.getDownloadURL();
      updates['storagePath'] = storagePath;
    }

    await _banners.doc(bannerId).update(updates);
  }

  Future<void> deleteBanner(AdminHomeBanner banner) async {
    await _banners.doc(banner.id).delete();
    try {
      await _storage.refFromURL(banner.imageUrl).delete();
    } catch (_) {
      // Storage 쪽 파일이 이미 없거나 URL 형식이 예상과 다르면, 색인
      // 문서만 지워도 목록에서는 사라지므로 조용히 넘어간다.
    }
  }

  Future<void> reorder(List<String> orderedBannerIds) async {
    final batch = _firestore.batch();
    for (var i = 0; i < orderedBannerIds.length; i++) {
      batch.update(_banners.doc(orderedBannerIds[i]), {'sortOrder': i});
    }
    await batch.commit();
  }
}
