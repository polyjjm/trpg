import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/writer_notice.dart';

/// writerNotices 컬렉션. packId 필드로 스토리팩별 공지를 걸러 볼 수 있다.
class AdminNoticeRepository {
  AdminNoticeRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _notices =>
      _firestore.collection('writerNotices');

  Stream<List<WriterNotice>> watchNoticesForPack(String packId) {
    return _notices
        .where('packId', isEqualTo: packId)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => WriterNotice.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> createNotice({
    required String packId,
    required String title,
    required String body,
  }) async {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    await _notices.add(
      WriterNotice(
        id: '',
        packId: packId,
        title: title,
        body: body,
        date: date,
      ).toJson(),
    );
  }

  Future<void> deleteNotice(String noticeId) async {
    await _notices.doc(noticeId).delete();
  }
}
