import 'package:flutter/material.dart';

/// 이 팩에서 아직 승인 요청을 안 보낸 변경사항의 개수 + 그 요청을 실제로
/// 보내는 콜백.
class PackSubmitState {
  /// 임시저장만 됐거나 아직 저장도 안 된 채 편집 중인 노드 수.
  final int unsubmittedCount;

  /// "변경사항 전체 승인요청" — 확인 다이얼로그까지 StoryTabView가 맡는다.
  final VoidCallback onSubmitAll;

  const PackSubmitState({
    required this.unsubmittedCount,
    required this.onSubmitAll,
  });
}

/// 상단 바의 "변경사항 전체 승인요청" 버튼이 읽는 값.
///
/// 개수를 계산하는 건 StoryTabView(_refreshUnsubmittedNodes)인데 — 자기 세션
/// 캐시를 봐야 알 수 있다 — 버튼은 그보다 위에 있는 AuthorToolPage의 상단
/// 바에 있다. 그래서 둘을 잇는 통로가 필요하다.
///
/// 위젯 파라미터로 내려보내는 대신 이 전역 notifier를 쓴다: StoryTabView는
/// 팩을 바꿀 때마다 통째로 새로 만들어지고(ValueKey), 그 생성자는 이미
/// 파라미터가 여덟 개다 — 화면 전체에 하나뿐인 값을 위해 그 체인에 하나를
/// 더 끼우는 것보다, 쓰는 쪽 두 곳이 같은 notifier를 직접 보는 게 변경 범위가
/// 훨씬 작다. 작가 도구는 한 번에 한 팩만 편집하므로 전역이어도 충돌하지
/// 않는다(값을 쓰는 StoryTabView가 언제나 하나뿐이다).
///
/// null이면 버튼을 숨긴다 — 보낼 변경사항이 없을 때도 마찬가지다.
final ValueNotifier<PackSubmitState?> packSubmitState = ValueNotifier(null);
