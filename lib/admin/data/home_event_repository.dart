import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/home_event.dart';

/// homeEvents 컬렉션(색인) + Firebase Storage(실제 이벤트 이미지)를 함께
/// 다루는 저장소 — HomeBannerRepository(admin)와 완전히 같은 구조다. "홈
/// 이벤트 관리" 섹션(HomeEventManagementSection)의 CRUD + 드래그 재정렬을
/// 담당한다.
class HomeEventRepository {
  HomeEventRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('homeEvents');

  /// 관리자 화면 전용 — 비활성/기간 만료 이벤트까지 전부 보여준다(리더 쪽
  /// HomeEventRepository 리더 사본의 watchActiveEvents가 노출 필터링을
  /// 따로 한다).
  Stream<List<AdminHomeEvent>> watchAllEvents() {
    return _events.orderBy('sortOrder').snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => AdminHomeEvent.fromFirestore(doc.id, doc.data()))
          .toList(),
    );
  }

  /// 새 이벤트를 만든다 — 이미지를 Storage(admin/home_events/{eventId}.jpg,
  /// HomeBannerRepository와 같은 고정 확장자 패턴)에 올리고, 다운로드 URL과
  /// 나머지 필드를 함께 문서로 쓴다.
  Future<void> createEvent({
    required Uint8List imageBytes,
    required String? title,
    required String? linkedPackId,
    required int sortOrder,
    required bool active,
    required DateTime? startDate,
    required DateTime? endDate,
  }) async {
    final doc = _events.doc();
    final ref = _storage.ref('admin/home_events/${doc.id}.jpg');
    await ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
    final imageUrl = await ref.getDownloadURL();

    await doc.set({
      'imageUrl': imageUrl,
      'title': title,
      'linkedPackId': linkedPackId,
      'sortOrder': sortOrder,
      'active': active,
      'startDate': startDate != null ? Timestamp.fromDate(startDate) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate) : null,
    });
  }

  /// 기존 이벤트를 고친다. [imageBytes]를 주면 같은 경로(파일명이 eventId라
  /// 자동으로 같은 자리)에 덮어써 이미지를 교체하고, null이면 기존 imageUrl을
  /// 건드리지 않는다.
  Future<void> updateEvent(
    String eventId, {
    Uint8List? imageBytes,
    required String? title,
    required String? linkedPackId,
    required int sortOrder,
    required bool active,
    required DateTime? startDate,
    required DateTime? endDate,
  }) async {
    final updates = <String, dynamic>{
      'title': title,
      'linkedPackId': linkedPackId,
      'sortOrder': sortOrder,
      'active': active,
      'startDate': startDate != null ? Timestamp.fromDate(startDate) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate) : null,
    };

    if (imageBytes != null) {
      final ref = _storage.ref('admin/home_events/$eventId.jpg');
      await ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
      updates['imageUrl'] = await ref.getDownloadURL();
    }

    await _events.doc(eventId).update(updates);
  }

  Future<void> deleteEvent(AdminHomeEvent event) async {
    await _events.doc(event.id).delete();
    try {
      await _storage.refFromURL(event.imageUrl).delete();
    } catch (_) {
      // Storage 쪽 파일이 이미 없거나 URL 형식이 예상과 다르면, 색인
      // 문서만 지워도 목록에서는 사라지므로 조용히 넘어간다.
    }
  }

  /// 드래그로 바뀐 순서 그대로 sortOrder를 0부터 다시 매겨 한 번에 쓴다 —
  /// HomeBannerRepository.reorder와 같은 방식.
  Future<void> reorder(List<String> orderedEventIds) async {
    final batch = _firestore.batch();
    for (var i = 0; i < orderedEventIds.length; i++) {
      batch.update(_events.doc(orderedEventIds[i]), {'sortOrder': i});
    }
    await batch.commit();
  }
}
