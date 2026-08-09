import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/admin_image.dart';

/// images 컬렉션(색인) + Firebase Storage(실제 파일)를 함께 다루는 저장소.
class AdminImageRepository {
  AdminImageRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _images =>
      _firestore.collection('images');

  Stream<List<AdminImage>> watchImages() {
    return _images.orderBy('name').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminImage.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// 이미지를 Storage에 업로드하고, 다운로드 URL을 images 문서로 색인한다.
  Future<AdminImage> uploadImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final doc = _images.doc();
    final ref = _storage.ref('admin/story_images/${doc.id}_$fileName');

    await ref.putData(bytes);
    final url = await ref.getDownloadURL();

    await doc.set({'name': fileName, 'url': url});

    return AdminImage(id: doc.id, name: fileName, url: url);
  }

  Future<void> deleteImage(AdminImage image) async {
    await _images.doc(image.id).delete();
    try {
      await _storage.refFromURL(image.url).delete();
    } catch (_) {
      // Storage 쪽 파일이 이미 없거나 URL 형식이 예상과 다르면, 색인 문서만
      // 지워도 목록에서는 사라지므로 조용히 넘어간다.
    }
  }
}
