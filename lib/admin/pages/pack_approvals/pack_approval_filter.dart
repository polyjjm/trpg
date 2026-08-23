import '../../models/admin_story_pack.dart';

/// 요청 시각 포맷 함수(formatWaitedLabel/formatRequestedDate)는
/// approvals/approval_filter.dart의 것을 그대로 재사용한다 — 순수
/// DateTime 포맷터라 팩/노드 구분과 무관하다. 쓰는 쪽에서 직접 import한다.

/// 스토리팩 승인 화면의 대기 항목 하나 — 연재 시작 요청 또는 메타데이터
/// 변경 요청. 두 스트림(watchPendingSerializationRequests/
/// watchPendingMetadataEdits)에서 온 [AdminStoryPack]을 요청 유형과 함께
/// 감싸서, 승인 대기함(ApprovalsTab)과 같은 "목록 + 상세" 2단 패턴을 그대로
/// 쓸 수 있게 한다.
enum PackRequestKind { serialization, metadataEdit }

extension PackRequestKindLabel on PackRequestKind {
  String get label => switch (this) {
    PackRequestKind.serialization => '연재 시작',
    PackRequestKind.metadataEdit => '정보 변경',
  };
}

class PendingPackRequest {
  final AdminStoryPack pack;
  final PackRequestKind kind;

  const PendingPackRequest({required this.pack, required this.kind});

  DateTime? get requestedAt => kind == PackRequestKind.serialization
      ? pack.serializationSubmittedAt
      : pack.metadataSubmittedAt;

  /// 한 팩이 두 요청을 동시에 갖는 일은 없다 — 연재 승인 전엔 메타데이터
  /// 수정 요청 자체가 불가능하다([AdminStoryPack.canRequestMetadataEdit]).
  /// 그래도 유형까지 키에 넣어 명시적으로 구분해 둔다.
  String get key => '${kind.name}/${pack.id}';
}

enum PackRequestTypeFilter { all, serialization, metadataEdit }

extension PackRequestTypeFilterLabel on PackRequestTypeFilter {
  String get label => switch (this) {
    PackRequestTypeFilter.all => '전체',
    PackRequestTypeFilter.serialization => '연재 시작',
    PackRequestTypeFilter.metadataEdit => '정보 변경',
  };

  bool matches(PackRequestKind kind) => switch (this) {
    PackRequestTypeFilter.all => true,
    PackRequestTypeFilter.serialization =>
      kind == PackRequestKind.serialization,
    PackRequestTypeFilter.metadataEdit => kind == PackRequestKind.metadataEdit,
  };
}

/// 요청일 기준 기간 필터 — approvals/approval_filter.dart의
/// ApprovalDateRange와 같은 모양이지만, 팩 요청 목록은 [AdminStoryPack]을
/// 다뤄 타입이 달라 독립된 열거형으로 둔다.
enum PackApprovalDateRange { all, today, week, custom }

extension PackApprovalDateRangeLabel on PackApprovalDateRange {
  String get label => switch (this) {
    PackApprovalDateRange.all => '전체',
    PackApprovalDateRange.today => '오늘',
    PackApprovalDateRange.week => '7일',
    PackApprovalDateRange.custom => '직접 지정',
  };
}

enum PackApprovalSort { oldestFirst, newestFirst }

class PackApprovalFilter {
  /// 작가 이름 / 작품 제목을 한 칸에서 찾는다.
  final String query;
  final PackRequestTypeFilter type;
  final PackApprovalDateRange range;

  /// [PackApprovalDateRange.custom]일 때만 쓴다. [to]는 그 날 23:59:59까지 포함한다.
  final DateTime? from;
  final DateTime? to;
  final PackApprovalSort sort;

  const PackApprovalFilter({
    this.query = '',
    this.type = PackRequestTypeFilter.all,
    this.range = PackApprovalDateRange.all,
    this.from,
    this.to,
    this.sort = PackApprovalSort.oldestFirst,
  });

  PackApprovalFilter copyWith({
    String? query,
    PackRequestTypeFilter? type,
    PackApprovalDateRange? range,
    DateTime? from,
    DateTime? to,
    PackApprovalSort? sort,
  }) {
    return PackApprovalFilter(
      query: query ?? this.query,
      type: type ?? this.type,
      range: range ?? this.range,
      from: from ?? this.from,
      to: to ?? this.to,
      sort: sort ?? this.sort,
    );
  }
}

/// [requests]에 필터를 적용하고 정렬한다. 요청 시각을 모르는 항목(이론상
/// 있을 수 없지만 대비 차원)은 기간 필터가 걸리면 제외되고, 정렬에서는
/// 항상 맨 뒤로 밀린다 — approvals/approval_filter.dart의
/// applyApprovalFilter와 같은 규칙이다.
List<PendingPackRequest> applyPackApprovalFilter(
  List<PendingPackRequest> requests,
  PackApprovalFilter filter, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final weekAgo = startOfToday.subtract(const Duration(days: 6));
  final query = filter.query.trim().toLowerCase();

  bool matchesDate(DateTime? requestedAt) {
    switch (filter.range) {
      case PackApprovalDateRange.all:
        return true;
      case PackApprovalDateRange.today:
        return requestedAt != null && !requestedAt.isBefore(startOfToday);
      case PackApprovalDateRange.week:
        return requestedAt != null && !requestedAt.isBefore(weekAgo);
      case PackApprovalDateRange.custom:
        if (requestedAt == null) return false;
        final from = filter.from;
        final to = filter.to;
        if (from != null &&
            requestedAt.isBefore(DateTime(from.year, from.month, from.day))) {
          return false;
        }
        if (to != null &&
            requestedAt.isAfter(
              DateTime(to.year, to.month, to.day, 23, 59, 59),
            )) {
          return false;
        }
        return true;
    }
  }

  bool matchesQuery(PendingPackRequest request) {
    if (query.isEmpty) return true;
    final haystack = [
      request.pack.authorName,
      request.pack.title,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  final result = requests.where((request) {
    if (!filter.type.matches(request.kind)) return false;
    if (!matchesDate(request.requestedAt)) return false;
    return matchesQuery(request);
  }).toList();

  result.sort((a, b) {
    final x = a.requestedAt;
    final y = b.requestedAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return filter.sort == PackApprovalSort.oldestFirst
        ? x.compareTo(y)
        : y.compareTo(x);
  });
  return result;
}

/// 코인 가격을 "1,000원" 형식으로 — 요청 사양("가격은 원화 포맷으로")에
/// 맞춘 표기다. 실제 저장 필드는 코인 단위([AdminStoryPack.price] 참고)지만
/// 화면 표기 형식만 원화 관례(천 단위 콤마 + '원')를 따른다.
String formatWon(int amount) {
  final text = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return '${amount < 0 ? '-' : ''}$buffer원';
}
