import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/admin_sfx.dart';
import '../models/admin_sfx_category.dart';

/// sfxLibrary 컬렉션(색인) + Firebase Storage(실제 파일)를 함께 다루는
/// 저장소 — AdminImageRepository와 같은 구조다.
class AdminSfxRepository {
  AdminSfxRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _sfxLibrary =>
      _firestore.collection('sfxLibrary');

  Stream<List<AdminSfx>> watchSfxLibrary() {
    return _sfxLibrary
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminSfx.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// 효과음 파일을 Storage에 업로드하고, 다운로드 URL을 sfxLibrary 문서로
  /// 색인한다. Storage 경로는 원본 파일명이 아니라 고정 `.mp3` 확장자를
  /// 쓴다(FIRESTORE_SCHEMA.md에 정해진 admin/story_sfx/{sfxId}.mp3 패턴) —
  /// images처럼 원본 파일명을 그대로 이어붙이지 않는다.
  Future<AdminSfx> uploadSfx({
    required Uint8List bytes,
    required String fileName,
    required AdminSfxCategory category,
    required String? uploadedBy,
  }) async {
    final doc = _sfxLibrary.doc();
    final ref = _storage.ref('admin/story_sfx/${doc.id}.mp3');

    await ref.putData(bytes);
    final url = await ref.getDownloadURL();

    await doc.set({
      'name': fileName,
      'category': category.wireValue,
      'storageUrl': url,
      'uploadedBy': uploadedBy,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return AdminSfx(
      id: doc.id,
      name: fileName,
      category: category,
      storageUrl: url,
      uploadedBy: uploadedBy,
      createdAt: DateTime.now(),
    );
  }

  /// 카드의 "카테고리 변경"에서 쓴다 — ImageLibraryTab의 같은 동작과 이유가 같다.
  Future<void> updateCategory(String sfxId, AdminSfxCategory category) async {
    await _sfxLibrary.doc(sfxId).update({'category': category.wireValue});
  }

  Future<void> deleteSfx(AdminSfx sfx) async {
    await _sfxLibrary.doc(sfx.id).delete();
    try {
      await _storage.refFromURL(sfx.storageUrl).delete();
    } catch (_) {
      // Storage 쪽 파일이 이미 없거나 URL 형식이 예상과 다르면, 색인
      // 문서만 지워도 목록에서는 사라지므로 조용히 넘어간다.
    }
  }
}
