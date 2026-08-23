import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/admin_bgm.dart';

/// bgmLibrary 컬렉션(색인) + Firebase Storage(실제 파일)를 함께 다루는
/// 저장소 — AdminSfxRepository와 같은 구조다(category만 없다).
class AdminBgmRepository {
  AdminBgmRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _bgmLibrary =>
      _firestore.collection('bgmLibrary');

  Stream<List<AdminBgm>> watchBgmLibrary() {
    return _bgmLibrary
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminBgm.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// BGM 파일을 Storage에 업로드하고, 다운로드 URL을 bgmLibrary 문서로
  /// 색인한다. Storage 경로는 원본 파일명이 아니라 고정 `.mp3` 확장자를
  /// 쓴다 — AdminSfxRepository.uploadSfx와 같은 이유(admin/story_bgm/{bgmId}.mp3).
  Future<AdminBgm> uploadBgm({
    required Uint8List bytes,
    required String fileName,
    required String? uploadedBy,
  }) async {
    final doc = _bgmLibrary.doc();
    final ref = _storage.ref('admin/story_bgm/${doc.id}.mp3');

    await ref.putData(bytes);
    final url = await ref.getDownloadURL();

    await doc.set({
      'name': fileName,
      'storageUrl': url,
      'uploadedBy': uploadedBy,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return AdminBgm(
      id: doc.id,
      name: fileName,
      storageUrl: url,
      uploadedBy: uploadedBy,
      createdAt: DateTime.now(),
    );
  }

  Future<void> deleteBgm(AdminBgm bgm) async {
    await _bgmLibrary.doc(bgm.id).delete();
    try {
      await _storage.refFromURL(bgm.storageUrl).delete();
    } catch (_) {
      // Storage 쪽 파일이 이미 없거나 URL 형식이 예상과 다르면, 색인
      // 문서만 지워도 목록에서는 사라지므로 조용히 넘어간다.
    }
  }
}
