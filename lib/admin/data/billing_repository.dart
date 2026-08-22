import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/revenue_snapshot.dart';
import '../models/wallet_transaction.dart';

/// 결제내역/코인사용내역 탭에 넘길 필터 값 — 둘 다 AND로 합쳐진다.
///
/// [startDate]/[endDate]는 createdAt 범위, [uidQuery]는 uid 정확히 일치,
/// [nameQuery]는 displayName 접두어 검색, [minAmountKRW]/[maxAmountKRW]는
/// 결제내역 전용(결제금액 범위).
///
/// ⚠️ **의도적 단순화**: Firestore 쿼리 하나에는 범위(부등호) 조건을 가진
/// 필드가 최대 하나만 orderBy와 안전하게 맞물릴 수 있다(그 이상은 복합
/// 색인/정렬이 꼬이기 쉽다 — 이 프로젝트가 다른 곳에서도 반복해서 택한
/// 원칙, 예: HomeBannerRepository의 active+기간 필터링을 서버 대신
/// 클라이언트에서 조합하는 것과 같은 이유). 그래서:
/// - [nameQuery]가 있으면 서버 쿼리의 범위/정렬 기준 필드가 createdAt에서
///   displayName으로 바뀐다 — 그동안 [startDate]/[endDate]는 서버 쿼리에
///   들어가지 않고, 그 페이지 안에서 클라이언트로만 좁혀진다.
/// - [minAmountKRW]/[maxAmountKRW]는 항상 클라이언트에서만 좁힌다(결제금액
///   자체를 범위 필드로 쓰면 createdAt/displayName 둘 다와 충돌한다).
/// - [uidQuery]는 동등 필터라 항상 서버 쿼리에 그대로 들어간다(어느
///   모드와도 충돌하지 않는다).
///
/// 이 단순화 때문에 클라이언트 필터가 걸린 페이지는 실제 페이지 크기보다
/// 적은 행만 보일 수 있다 — 페이지네이션 커서 자체는 항상 원본(필터 전)
/// 조회 결과 기준이라 "다음"을 계속 누르면 끝까지 훑을 수 있다.
class AdminBillingFilter {
  final DateTime? startDate;
  final DateTime? endDate;
  final String? uidQuery;
  final String? nameQuery;
  final int? minAmountKRW;
  final int? maxAmountKRW;

  const AdminBillingFilter({
    this.startDate,
    this.endDate,
    this.uidQuery,
    this.nameQuery,
    this.minAmountKRW,
    this.maxAmountKRW,
  });

  bool get isNameSearch => (nameQuery?.trim().isNotEmpty ?? false);

  static const empty = AdminBillingFilter();
}

/// 커서 기반 페이지네이션 결과 — [lastDoc]을 다음 조회의 startAfter로 넘기면
/// 이어서 읽는다. [items]는 필터 적용 후(클라이언트 좁히기 포함) 개수라
/// 페이지 크기보다 적을 수 있다(AdminBillingFilter 문서 참고) — [hasMore]는
/// 필터 적용 전(원본 조회) 기준이라 "다음" 버튼이 항상 정확하다.
class BillingPage<T> {
  final List<T> items;
  final QueryDocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const BillingPage({required this.items, required this.lastDoc, required this.hasMore});

  static BillingPage<T> empty<T>() =>
      BillingPage<T>(items: const [], lastDoc: null, hasMore: false);
}

/// collectionGroup('transactions') — admin 결제내역/코인사용내역/정산내역
/// 화면 전용. firestore.rules의 `{path=**}/transactions` 규칙이 admin에게만
/// 이 collectionGroup 조회를 허용한다.
class AdminBillingRepository {
  AdminBillingRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const int pageSize = 20;

  Query<Map<String, dynamic>> _baseQuery(String type, AdminBillingFilter filter) {
    Query<Map<String, dynamic>> q = _firestore
        .collectionGroup('transactions')
        .where('type', isEqualTo: type);

    if (filter.uidQuery != null && filter.uidQuery!.trim().isNotEmpty) {
      q = q.where('uid', isEqualTo: filter.uidQuery!.trim());
    }

    if (filter.isNameSearch) {
      final name = filter.nameQuery!.trim();
      q = q
          .where('displayName', isGreaterThanOrEqualTo: name)
          .where('displayName', isLessThan: '$name')
          .orderBy('displayName')
          .orderBy('createdAt', descending: true);
    } else {
      if (filter.startDate != null) {
        q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(filter.startDate!));
      }
      if (filter.endDate != null) {
        q = q.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(filter.endDate!));
      }
      q = q.orderBy('createdAt', descending: true);
    }
    return q;
  }

  bool _passesClientFilter(DateTime? createdAt, AdminBillingFilter filter) {
    if (filter.isNameSearch) {
      if (filter.startDate != null && (createdAt == null || createdAt.isBefore(filter.startDate!))) {
        return false;
      }
      if (filter.endDate != null && (createdAt == null || createdAt.isAfter(filter.endDate!))) {
        return false;
      }
    }
    return true;
  }

  Future<BillingPage<AdminChargeTransaction>> fetchCharges({
    required AdminBillingFilter filter,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    var q = _baseQuery('charge', filter).limit(pageSize + 1);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snapshot = await q.get();

    final hasMore = snapshot.docs.length > pageSize;
    final pageDocs = hasMore ? snapshot.docs.sublist(0, pageSize) : snapshot.docs;

    var items = pageDocs.map(AdminChargeTransaction.fromFirestore).toList();
    items = items.where((t) => _passesClientFilter(t.createdAt, filter)).toList();
    if (filter.minAmountKRW != null) {
      items = items.where((t) => t.amountKRW >= filter.minAmountKRW!).toList();
    }
    if (filter.maxAmountKRW != null) {
      items = items.where((t) => t.amountKRW <= filter.maxAmountKRW!).toList();
    }

    return BillingPage(
      items: items,
      lastDoc: pageDocs.isEmpty ? null : pageDocs.last,
      hasMore: hasMore,
    );
  }

  Future<BillingPage<AdminPurchaseTransaction>> fetchPurchases({
    required AdminBillingFilter filter,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    var q = _baseQuery('purchase', filter).limit(pageSize + 1);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snapshot = await q.get();

    final hasMore = snapshot.docs.length > pageSize;
    final pageDocs = hasMore ? snapshot.docs.sublist(0, pageSize) : snapshot.docs;

    var items = pageDocs.map(AdminPurchaseTransaction.fromFirestore).toList();
    items = items.where((t) => _passesClientFilter(t.createdAt, filter)).toList();

    return BillingPage(
      items: items,
      lastDoc: pageDocs.isEmpty ? null : pageDocs.last,
      hasMore: hasMore,
    );
  }

  static String dateKeyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// [startDate]~[endDate](둘 다 포함, KST 날짜 기준) 사이의 revenueSnapshots
  /// 문서를 전부 읽는다. 아직 집계되지 않은 날짜(오늘 등)는 문서 자체가
  /// 없어서 결과에서 빠진다 — 호출부가 "오늘은 다음날 집계돼요" 같은
  /// 안내를 따로 보여줘야 한다. Firestore whereIn은 한 번에 최대 30개라,
  /// 범위가 길면(예: "직접 지정"으로 두 달을 고르면) 30일씩 나눠 조회한다.
  Future<List<AdminRevenueSnapshot>> fetchRevenueRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final keys = <String>[];
    for (var d = DateTime(startDate.year, startDate.month, startDate.day);
        !d.isAfter(endDate);
        d = d.add(const Duration(days: 1))) {
      keys.add(dateKeyOf(d));
    }
    if (keys.isEmpty) return const [];

    final results = <AdminRevenueSnapshot>[];
    for (var i = 0; i < keys.length; i += 30) {
      final chunk = keys.sublist(i, i + 30 > keys.length ? keys.length : i + 30);
      final snapshot = await _firestore
          .collection('revenueSnapshots')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(
        snapshot.docs.map((doc) => AdminRevenueSnapshot.fromFirestore(doc.id, doc.data())),
      );
    }
    results.sort((a, b) => a.dateKey.compareTo(b.dateKey));
    return results;
  }
}
