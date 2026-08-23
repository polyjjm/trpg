import 'package:cloud_firestore/cloud_firestore.dart';

/// activityLog/{autoId} 문서 하나 — 관리자 개요의 "최근 활동" 카드 전용.
///
/// 감사 로그가 아니라 **읽기 편한 타임라인**이다. 그래서 구조화된 필드
/// (before/after diff 등)를 두지 않고, 기록하는 쪽이 완성된 한 줄
/// ([message])을 그대로 넣는다 — 화면이 문구를 조립하려 들면 활동 종류가
/// 늘어날 때마다 화면을 고쳐야 한다.
enum ActivityKind {
  nodeApproved,
  nodeRejected,
  packSerializationApproved,
  packMetadataApproved,
  authorApproved,
  authorRejected,
  productChanged,
  bannerChanged,
  noticeChanged,
}

extension ActivityKindJson on ActivityKind {
  String get wireValue => name;

  static ActivityKind fromWire(String? value) {
    return ActivityKind.values.firstWhere(
      (k) => k.name == value,
      orElse: () => ActivityKind.productChanged,
    );
  }
}

class ActivityEvent {
  final String id;
  final ActivityKind kind;

  /// 이미 완성된 한 줄. 예: '조민서 · 「기억을 파는 가게」 시즌 2 연재 승인'
  final String message;

  /// 이 활동을 일으킨 관리자 uid — 화면에는 안 쓰지만 나중에 "누가 했나"를
  /// 되짚을 수 있어야 해서 남긴다.
  final String? actorUid;
  final DateTime? createdAt;

  const ActivityEvent({
    required this.id,
    required this.kind,
    required this.message,
    this.actorUid,
    this.createdAt,
  });

  factory ActivityEvent.fromFirestore(String id, Map<String, dynamic> json) {
    return ActivityEvent(
      id: id,
      kind: ActivityKindJson.fromWire(json['kind'] as String?),
      message: json['message'] as String? ?? '',
      actorUid: json['actorUid'] as String?,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
