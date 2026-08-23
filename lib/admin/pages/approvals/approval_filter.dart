import '../../models/activity_event.dart';
import '../../models/pending_action.dart';
import '../../models/pending_node_ref.dart';

/// 승인 대기함의 필터/정렬 상태와 그 적용 로직 — 위젯에서 떼어냈다. 이 계산은
/// 전부 클라이언트에서 한다(Firestore 쿼리를 늘리지 않는다): `watchPendingNodes()`가
/// 이미 모든 대기 노드를 들고 오고, 대기 건수는 본질적으로 "쌓이면 안 되는"
/// 수치라 수천 건이 되는 상황 자체가 이상 신호다. 서버 필터로 옮기는 건 복합
/// 색인을 늘리는 대가만 있고 얻는 게 없다.
enum ApprovalKindFilter { all, create, edit, delete }

/// 요청일(approvalRequestedAt) 기준 기간 필터.
enum ApprovalDateRange { all, today, week, custom }

enum ApprovalSort { oldestFirst, newestFirst }

/// 승인 대기함이 지금 무엇을 보여주는지 — 대기 중인 요청(기존 동작, 기본값)
/// 인지, 이미 처리된 이력(activityLog의 nodeApproved/nodeRejected)인지,
/// 둘 다인지. [ApprovalFilter]의 다른 필드(검색/기간/정렬)와 달리 이 값은
/// 데이터 소스 자체를 가른다 — `PendingNodeRef` 목록과 `ActivityEvent`
/// 목록은 서로 다른 스트림에서 온다(approvals_tab.dart 참고).
enum ApprovalStatusFilter { pending, handled, all }

extension ApprovalStatusFilterLabel on ApprovalStatusFilter {
  String get label => switch (this) {
    ApprovalStatusFilter.pending => '대기중',
    ApprovalStatusFilter.handled => '처리됨',
    ApprovalStatusFilter.all => '전체',
  };
}

extension ApprovalKindFilterLabel on ApprovalKindFilter {
  String get label => switch (this) {
    ApprovalKindFilter.all => '전체',
    ApprovalKindFilter.create => '등록',
    ApprovalKindFilter.edit => '수정',
    ApprovalKindFilter.delete => '삭제',
  };

  PendingAction? get action => switch (this) {
    ApprovalKindFilter.all => null,
    ApprovalKindFilter.create => PendingAction.create,
    ApprovalKindFilter.edit => PendingAction.edit,
    ApprovalKindFilter.delete => PendingAction.delete,
  };
}

extension ApprovalDateRangeLabel on ApprovalDateRange {
  String get label => switch (this) {
    ApprovalDateRange.all => '전체',
    ApprovalDateRange.today => '오늘',
    ApprovalDateRange.week => '7일',
    ApprovalDateRange.custom => '직접 지정',
  };
}

class ApprovalFilter {
  /// 작가 이름 / 작품 제목 / 노드 ID를 한 칸에서 찾는다 — 운영자가 "누가
  /// 요청했는지"로 찾는 경우가 가장 많아서 작가 이름을 첫 번째 대상으로 둔다.
  final String query;
  final ApprovalKindFilter kind;
  final ApprovalDateRange range;

  /// [ApprovalDateRange.custom]일 때만 쓴다. [to]는 그 날 23:59:59까지 포함한다.
  final DateTime? from;
  final DateTime? to;
  final ApprovalSort sort;

  /// 대기중(기본)/처리됨/전체 — 위 [ApprovalStatusFilter] 참고.
  final ApprovalStatusFilter status;

  const ApprovalFilter({
    this.query = '',
    this.kind = ApprovalKindFilter.all,
    this.range = ApprovalDateRange.all,
    this.from,
    this.to,
    this.sort = ApprovalSort.oldestFirst,
    this.status = ApprovalStatusFilter.pending,
  });

  ApprovalFilter copyWith({
    String? query,
    ApprovalKindFilter? kind,
    ApprovalDateRange? range,
    DateTime? from,
    DateTime? to,
    ApprovalSort? sort,
    ApprovalStatusFilter? status,
  }) {
    return ApprovalFilter(
      query: query ?? this.query,
      kind: kind ?? this.kind,
      range: range ?? this.range,
      from: from ?? this.from,
      to: to ?? this.to,
      sort: sort ?? this.sort,
      status: status ?? this.status,
    );
  }
}

/// 한 스토리팩에 걸린 대기 요청 묶음 — 목록에서 작품 헤더 하나 + 그 아래 행들.
/// 같은 작품의 요청은 보통 한꺼번에 검토하게 되므로(같은 맥락, 같은 작가)
/// 평평한 목록보다 훨씬 빨리 읽힌다.
class PendingGroup {
  final String packId;
  final String packTitle;
  final String authorName;
  final List<PendingNodeRef> items;

  const PendingGroup({
    required this.packId,
    required this.packTitle,
    required this.authorName,
    required this.items,
  });
}

/// [refs]에 필터를 적용하고 정렬한다.
///
/// 요청 시각(`approvalRequestedAt`)이 없는 노드(그 필드가 도입되기 전에 제출된
/// 것)는 기간 필터가 걸리면 제외된다 — "언제 요청됐는지 모르는 것"을 특정
/// 기간에 넣을 근거가 없다. 기간이 [ApprovalDateRange.all]이면 그대로 남고,
/// 정렬에서는 항상 맨 뒤로 밀린다.
List<PendingNodeRef> applyApprovalFilter(
  List<PendingNodeRef> refs,
  ApprovalFilter filter, {
  required Map<String, String> packTitles,
  required Map<String, String> packAuthors,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final weekAgo = startOfToday.subtract(const Duration(days: 6));
  final query = filter.query.trim().toLowerCase();

  bool matchesDate(DateTime? requestedAt) {
    switch (filter.range) {
      case ApprovalDateRange.all:
        return true;
      case ApprovalDateRange.today:
        return requestedAt != null && !requestedAt.isBefore(startOfToday);
      case ApprovalDateRange.week:
        return requestedAt != null && !requestedAt.isBefore(weekAgo);
      case ApprovalDateRange.custom:
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

  bool matchesQuery(PendingNodeRef ref) {
    if (query.isEmpty) return true;
    final haystack = [
      packAuthors[ref.packId] ?? '',
      packTitles[ref.packId] ?? ref.packId,
      ref.node.id,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  final action = filter.kind.action;
  final result = refs.where((ref) {
    if (action != null && ref.node.pendingAction != action) return false;
    if (!matchesDate(ref.requestedAt)) return false;
    return matchesQuery(ref);
  }).toList();

  result.sort((a, b) {
    final x = a.requestedAt;
    final y = b.requestedAt;
    // 시각을 모르는 노드는 어느 정렬에서도 맨 뒤 — 판단 근거가 없는 항목을
    // 목록 맨 위에 올려두면 매번 눈에 걸린다.
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return filter.sort == ApprovalSort.oldestFirst
        ? x.compareTo(y)
        : y.compareTo(x);
  });
  return result;
}

/// 정렬 순서를 유지한 채 팩 단위로 묶는다 — 먼저 등장한 팩이 먼저 온다(가장
/// 오래 기다린 요청이 있는 작품이 위로 올라온다).
List<PendingGroup> groupPendingByPack(
  List<PendingNodeRef> refs, {
  required Map<String, String> packTitles,
  required Map<String, String> packAuthors,
}) {
  final order = <String>[];
  final buckets = <String, List<PendingNodeRef>>{};

  for (final ref in refs) {
    final list = buckets.putIfAbsent(ref.packId, () {
      order.add(ref.packId);
      return <PendingNodeRef>[];
    });
    list.add(ref);
  }

  return [
    for (final packId in order)
      PendingGroup(
        packId: packId,
        packTitle: packTitles[packId] ?? packId,
        authorName: packAuthors[packId] ?? '-',
        items: buckets[packId]!,
      ),
  ];
}

/// 대기 시간 라벨 — 개요의 formatWaited와 달리 "오늘"을 따로 쓴다(목록에서
/// "0일"은 읽히지 않는다).
String formatWaitedLabel(DateTime? requestedAt, {DateTime? now}) {
  if (requestedAt == null) return '-';
  final diff = (now ?? DateTime.now()).difference(requestedAt);
  if (diff.inHours < 1) return '방금';
  if (diff.inDays < 1) return '${diff.inHours}시간';
  return '${diff.inDays}일';
}

String formatRequestedDate(DateTime? requestedAt) {
  if (requestedAt == null) return '요청일 미기록';
  return '${requestedAt.year}.${requestedAt.month.toString().padLeft(2, '0')}.'
      '${requestedAt.day.toString().padLeft(2, '0')}';
}

/// [applyApprovalFilter]의 처리 이력판 — 검색(작가/작품/노드 ID)과 기간
/// 필터만 적용한다(요청 사양: "처리 이력에도 기존 검색과 기간 필터가
/// 걸려야 한다"). 요청 유형(등록/수정/삭제) 필터는 적용하지 않는다 —
/// [ActivityEvent]에는 pendingAction 개념 자체가 없다(이미 끝난 일이라
/// "지금 어떤 요청인지"를 묻는 게 의미가 없다). 정렬 기준은 [createdAt]
/// (기록된 시각)이다 — 대기 목록의 [requestedAt](요청 시각)과는 다른
/// 필드지만 같은 "언제 일어난 일인지" 역할을 한다.
///
/// [packId]/[authorName]이 없는(이 필드들이 생기기 전에 기록된) 옛 문서는
/// 검색어로 못 찾는다 — 되짚어 채울 원본 데이터가 없으니 어쩔 수 없다.
///
/// 필터를 통째로(`ApprovalFilter`) 받지 않고 [query]/[range]/[from]/[to]/
/// [sort] 다섯 값만 받는다 — 승인 대기함(노드) 전용 `ApprovalFilter`뿐
/// 아니라 스토리팩 승인(`PackApprovalFilter`)/작가 신청도 이 함수를 그대로
/// 재사용한다. 필터 클래스마다 [ApprovalDateRange]/[ApprovalSort] 타입은
/// 공유하지만 클래스 자체는 서로 다르므로(kind/type 등 나머지 필드가 다르다),
/// 다섯 값만 뽑아서 넘기는 편이 필터 클래스에 종속되지 않는다.
List<ActivityEvent> applyHistoryFilter(
  List<ActivityEvent> events, {
  required String query,
  required ApprovalDateRange range,
  DateTime? from,
  DateTime? to,
  required ApprovalSort sort,
  required Map<String, String> packTitles,
  required Map<String, String> packAuthors,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final weekAgo = startOfToday.subtract(const Duration(days: 6));
  final normalizedQuery = query.trim().toLowerCase();

  bool matchesDate(DateTime? createdAt) {
    switch (range) {
      case ApprovalDateRange.all:
        return true;
      case ApprovalDateRange.today:
        return createdAt != null && !createdAt.isBefore(startOfToday);
      case ApprovalDateRange.week:
        return createdAt != null && !createdAt.isBefore(weekAgo);
      case ApprovalDateRange.custom:
        if (createdAt == null) return false;
        if (from != null &&
            createdAt.isBefore(DateTime(from.year, from.month, from.day))) {
          return false;
        }
        if (to != null &&
            createdAt.isAfter(
              DateTime(to.year, to.month, to.day, 23, 59, 59),
            )) {
          return false;
        }
        return true;
    }
  }

  bool matchesQuery(ActivityEvent event) {
    if (normalizedQuery.isEmpty) return true;
    final packId = event.packId;
    final haystack = [
      event.authorName ?? (packId == null ? '' : packAuthors[packId] ?? ''),
      packId == null ? '' : (packTitles[packId] ?? packId),
      event.nodeId ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(normalizedQuery);
  }

  final result = events
      .where((event) => matchesDate(event.createdAt) && matchesQuery(event))
      .toList();

  result.sort((a, b) {
    final x = a.createdAt;
    final y = b.createdAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return sort == ApprovalSort.oldestFirst ? x.compareTo(y) : y.compareTo(x);
  });
  return result;
}
