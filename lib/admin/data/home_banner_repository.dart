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

  /// 관리자 화면 전용 — 비활성/기간 만료 배너까지 전부 보여준다(리더 쪽
  /// 노출 필터링은 HomeBannerRepository 리더 사본의 watchActiveBanners가
  /// 따로 한다).
  Stream<List<AdminHomeBanner>> watchAllBanners() {
    return _banners.orderBy('sortOrder').snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => AdminHomeBanner.fromFirestore(doc.id, doc.data()))
          .toList(),
    );
  }

  /// 새 배너를 만든다 — 이미지를 Storage(admin/home_banners/{bannerId}.jpg,
  /// AdminSfxRepository의 고정 확장자 패턴과 같다)에 올리고, 다운로드 URL과
  /// 나머지 필드를 함께 문서로 쓴다. 이미지가 이제 배너의 핵심 콘텐츠라
  /// [imageBytes]는 필수다.
  ///
  /// SettableMetadata로 contentType을 명시적으로 image/jpeg로 지정한다 —
  /// 안 주면 Storage가 application/octet-stream으로 저장하는데, 실제로
  /// 겪은 버그로 그 상태에서는 리더 쪽 Image.network가 다운로드는 성공해도
  /// (바이트 자체는 멀쩡한 PNG/JPEG였다) 디코드에 실패해 항상 fallback
  /// 아이콘만 보였다. 원본이 PNG여도 image/jpeg로 표시해 두면(파일명도 이미
  /// 고정 .jpg다) 브라우저/Skia가 실제 매직 바이트로 디코드하므로 렌더링엔
  /// 문제없다 — 여기서 중요한 건 "image/*로 시작하는 뭔가"이지 정확한
  /// 서브타입이 아니다.
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
    final ref = _storage.ref('admin/home_banners/${doc.id}.jpg');
    await ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
    final imageUrl = await ref.getDownloadURL();

    await doc.set({
      'imageUrl': imageUrl,
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

  /// 기존 배너를 고친다. [imageBytes]를 주면 같은 경로(파일명이 bannerId라
  /// 자동으로 같은 자리)에 덮어써 이미지를 교체하고, null이면(사진은 그대로
  /// 두고 연결 팩/활성/기간만 바꾸는 편집) 기존 imageUrl을 건드리지 않는다.
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
      final ref = _storage.ref('admin/home_banners/$bannerId.jpg');
      await ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
      updates['imageUrl'] = await ref.getDownloadURL();
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

  /// 드래그로 바뀐 순서 그대로 sortOrder를 0부터 다시 매겨 한 번에 쓴다 —
  /// StoryNodeSidebar의 order 재정렬과 같은 방식(배치 하나로, 바뀐 문서만
  /// 최소 쓰기가 아니라 전체를 다시 매기는 단순한 방식을 택했다 — 배너
  /// 개수가 몇 개 안 돼서 최적화할 필요가 없다).
  Future<void> reorder(List<String> orderedBannerIds) async {
    final batch = _firestore.batch();
    for (var i = 0; i < orderedBannerIds.length; i++) {
      batch.update(_banners.doc(orderedBannerIds[i]), {'sortOrder': i});
    }
    await batch.commit();
  }
}
