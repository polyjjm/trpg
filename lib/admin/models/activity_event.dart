import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/admin_theme.dart';

/// activityLog/{autoId} 문서 하나 — 관리자 개요의 "최근 활동" 카드 +
/// 승인 대기함의 "처리 이력" 탭 전용.
///
/// 감사 로그가 아니라 **읽기 편한 타임라인**이다. 그래서 구조화된 필드
/// (before/after diff 등)를 두지 않고, 기록하는 쪽이 완성된 한 줄
/// ([message])을 그대로 넣는다 — 화면이 문구를 조립하려 들면 활동 종류가
/// 늘어날 때마다 화면을 고쳐야 한다.
enum ActivityKind {
  nodeApproved,
  nodeRejected,
  packSerializationApproved,
  packSerializationRejected,
  packMetadataApproved,
  packMetadataRejected,
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

/// 종류별 라벨/색 판정을 여기 한 곳에 모은다 — 화면(최근 활동 카드, 승인
/// 대기함 처리 이력 등)마다 switch를 따로 복사하면 종류가 하나 늘 때마다
/// 여러 곳을 같이 고쳐야 하고, 하나라도 빠뜨리면 화면마다 다른 색/라벨이
/// 나오는 어긋남이 생긴다.
///
/// [dotColor]는 요청 사양이 지정한 세 계열 그대로다: 승인계열은
/// [AdminColors.ok], 반려계열은 [AdminColors.danger], 상품/배너/공지는
/// [AdminColors.accent]. [badgeBg]/[badgeText]는 status_tag.dart의 "파스텔
/// bg + 진한 텍스트" 배지 관례를 따르되, 새 색을 만들지 않고 기존
/// [AdminColors] 값만 쓴다 — 승인은 이미 있는 파스텔 쌍(approveBg/Text,
/// 승인 버튼과 같은 색)을 그대로 재사용하고, 상품/배너/공지는 accent와 같은
/// 파란 계열의 기존 파스텔 쌍(imageCategoryBackgroundBg/Text)을 재사용한다.
/// 반려만 예외 — 팔레트에 "파스텔 빨강 + 진한 빨강 텍스트" 쌍이 아예 없어서
/// (rejectBg/Text는 반대로 어두운 배경 + 밝은 텍스트라 배지가 아니라 버튼용),
/// 새 색을 만드는 대신 [AdminColors.danger] 자체를 텍스트로, 그 색의 옅은
/// 음영(`withOpacity`)을 배경으로 파생시켜 쓴다 — 이것도 새 색이 아니라
/// 이미 지정된 danger의 변형일 뿐이다.
extension ActivityKindDisplay on ActivityKind {
  String get label => switch (this) {
    ActivityKind.nodeApproved => '노드 승인',
    ActivityKind.nodeRejected => '노드 반려',
    ActivityKind.packSerializationApproved => '연재 승인',
    ActivityKind.packSerializationRejected => '연재 반려',
    ActivityKind.packMetadataApproved => '작품정보 승인',
    ActivityKind.packMetadataRejected => '작품정보 반려',
    ActivityKind.authorApproved => '작가 승인',
    ActivityKind.authorRejected => '작가 반려',
    ActivityKind.productChanged => '상품',
    ActivityKind.bannerChanged => '배너',
    ActivityKind.noticeChanged => '공지',
  };

  bool get _isApprovalFamily => switch (this) {
    ActivityKind.nodeApproved ||
    ActivityKind.packSerializationApproved ||
    ActivityKind.packMetadataApproved ||
    ActivityKind.authorApproved => true,
    _ => false,
  };

  bool get _isRejectionFamily => switch (this) {
    ActivityKind.nodeRejected ||
    ActivityKind.packSerializationRejected ||
    ActivityKind.packMetadataRejected ||
    ActivityKind.authorRejected => true,
    _ => false,
  };

  Color get dotColor {
    if (_isApprovalFamily) return AdminColors.ok;
    if (_isRejectionFamily) return AdminColors.danger;
    return AdminColors.accent;
  }

  Color get badgeBg {
    if (_isApprovalFamily) return AdminColors.approveBg;
    if (_isRejectionFamily) return AdminColors.danger.withOpacity(0.14);
    return AdminColors.imageCategoryBackgroundBg;
  }

  Color get badgeText {
    if (_isApprovalFamily) return AdminColors.approveText;
    if (_isRejectionFamily) return AdminColors.danger;
    return AdminColors.imageCategoryBackgroundText;
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

  /// 승인 대기함의 "처리 이력" 탭이 검색(작가/작품/노드 ID)과 diff 없는
  /// 요약 표시에 쓴다 — [message]는 이미 완성된 문장이라 파싱해서 되짚을
  /// 수 없으므로, 검색 가능한 원본 필드를 구조화해서 따로 저장한다. 셋 다
  /// 선택([log] 호출부가 넘긴 경우만 채워진다) — 이 필드들이 생기기 전에
  /// 기록된 기존 문서에는 없으므로, 읽을 때 없어도 깨지지 않게 nullable로
  /// 그대로 둔다(검색/필터에서는 그런 옛 문서가 그냥 안 걸릴 뿐이다).
  final String? packId;
  final String? nodeId;
  final String? authorName;

  const ActivityEvent({
    required this.id,
    required this.kind,
    required this.message,
    this.actorUid,
    this.createdAt,
    this.packId,
    this.nodeId,
    this.authorName,
  });

  factory ActivityEvent.fromFirestore(String id, Map<String, dynamic> json) {
    return ActivityEvent(
      id: id,
      kind: ActivityKindJson.fromWire(json['kind'] as String?),
      message: json['message'] as String? ?? '',
      actorUid: json['actorUid'] as String?,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      packId: json['packId'] as String?,
      nodeId: json['nodeId'] as String?,
      authorName: json['authorName'] as String?,
    );
  }
}
