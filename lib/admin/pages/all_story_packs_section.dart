import 'package:flutter/material.dart';

import '../../core/user/user_profile.dart';
import '../../core/user/user_profile_repository.dart';
import '../data/activity_log_repository.dart';
import '../data/admin_story_repository.dart';
import '../models/activity_event.dart';
import '../models/admin_story_pack.dart';
import '../models/story_pack_type.dart';
import '../widgets/admin_theme.dart';
import 'approvals/approval_filter.dart'
    show ApprovalDateRange, ApprovalDateRangeLabel, formatRequestedDate;
import 'approvals/node_diff_view.dart'
    show ApprovalActionButton, promptRejectionReason;

/// "전체 작품 목록" — 모든 작가의 스토리팩을 가로질러 보여준다. 작가별로
/// 묶고, 작가 이름/작가 UID로 검색하고, 생성일 기간으로 좁힐 수 있다.
/// 팩 단위 "상태" 개념 자체가 아직 없어서(지금은 노드 단위로만 status가
/// 있다) 상태별 필터는 여전히 없다.
///
/// 검색/기간 필터는 전부 클라이언트에서 계산한다 — `watchPacks()`가 이미
/// 전체 목록을 불러오고, admin 대상 데이터셋은 유한하다는 전제라 서버 쿼리를
/// 늘릴 이유가 없다(approvals/approval_filter.dart와 같은 판단).
class AllStoryPacksSection extends StatefulWidget {
  final AdminStoryRepository storyRepository;
  final UserProfileRepository userProfileRepository;
  final String reviewerUid;

  /// 강제 내리기/복원을 개요의 "최근 활동"에 남긴다. null이면 기록하지 않는다.
  final ActivityLogRepository? activityLog;

  const AllStoryPacksSection({
    super.key,
    required this.storyRepository,
    required this.userProfileRepository,
    required this.reviewerUid,
    this.activityLog,
  });

  @override
  State<AllStoryPacksSection> createState() => _AllStoryPacksSectionState();
}

class _AllStoryPacksSectionState extends State<AllStoryPacksSection> {
  late final Stream<List<AdminStoryPack>> _packsStream = widget.storyRepository
      .watchPacks();

  /// 팩 목록에 등장하는 authorId 집합별로 캐시한다 — 같은 authorId 집합이면
  /// 재조회하지 않는다(매 packs 스냅샷마다 새 Future를 만들면 authorId 구성이
  /// 안 바뀌었어도 다시 조회하게 된다).
  final Map<String, Future<List<UserProfile>>> _authorProfilesCache = {};

  Future<List<UserProfile>> _authorProfilesFor(Set<String> authorIds) {
    final key = (authorIds.toList()..sort()).join(',');
    return _authorProfilesCache.putIfAbsent(
      key,
      () =>
          widget.userProfileRepository.fetchProfilesByUids(authorIds.toList()),
    );
  }

  String _query = '';
  ApprovalDateRange _range = ApprovalDateRange.all;
  DateTime? _from;
  DateTime? _to;

  /// 강제 내리기/복원 처리 중인 packId — 버튼 중복 클릭을 막는다(승인
  /// 대기함/스토리팩 승인의 _processingKeys와 같은 패턴).
  final Set<String> _processingKeys = {};

  Future<void> _log(AdminStoryPack pack, {required bool suspending}) async {
    final log = widget.activityLog;
    if (log == null) return;
    final authorLabel = pack.authorName.isEmpty
        ? '(작가 이름 없음)'
        : pack.authorName;
    await log.log(
      kind: suspending ? ActivityKind.packSuspended : ActivityKind.packRestored,
      actorUid: widget.reviewerUid,
      message: suspending
          ? '$authorLabel · 「${pack.title}」 강제 내리기'
          : '$authorLabel · 「${pack.title}」 복원',
      packId: pack.id,
      authorName: pack.authorName,
    );
  }

  Future<void> _handleTakedown(AdminStoryPack pack) async {
    if (_processingKeys.contains(pack.id)) return;
    final reason = await promptRejectionReason(context);
    if (reason == null || !mounted) return;

    setState(() => _processingKeys.add(pack.id));
    try {
      await widget.storyRepository.suspendPack(
        pack,
        reviewerUid: widget.reviewerUid,
        reason: reason,
      );
      await _log(pack, suspending: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('강제 내리기에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _processingKeys.remove(pack.id));
    }
  }

  Future<void> _handleRestore(AdminStoryPack pack) async {
    if (_processingKeys.contains(pack.id)) return;

    setState(() => _processingKeys.add(pack.id));
    try {
      await widget.storyRepository.unsuspendPack(pack);
      await _log(pack, suspending: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('복원에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _processingKeys.remove(pack.id));
    }
  }

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final initial =
        (isFrom ? _from : _to) ??
        DateTime.now().subtract(Duration(days: isFrom ? 7 : 0));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AdminColors.gold,
            brightness: AdminTheme.isDark ? Brightness.dark : Brightness.light,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '전체 작품 목록',
              style: TextStyle(
                fontSize: 16,
                color: AdminColors.ivory,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '모든 작가의 스토리팩이에요, 작가별로 묶어서 보여줘요. 상태별로 좁혀 보는 기능은 아직 없어요 — '
              '팩 단위 "상태" 개념 자체가 아직 없어서(지금은 노드 단위로만 있어요) 따로 설계해서 추가할 예정이에요.',
              style: TextStyle(
                fontSize: 12,
                color: AdminColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            _FilterBar(
              query: _query,
              range: _range,
              from: _from,
              to: _to,
              onQueryChanged: (value) => setState(() => _query = value),
              onRangeChanged: (value) => setState(() => _range = value),
              onPickFrom: () => _pickDate(context, isFrom: true),
              onPickTo: () => _pickDate(context, isFrom: false),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<AdminStoryPack>>(
              stream: _packsStream,
              builder: (context, packsSnapshot) {
                if (packsSnapshot.hasError) {
                  return SelectableText(
                    '작품 목록을 불러오지 못했어요: ${packsSnapshot.error}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.danger,
                    ),
                  );
                }
                if (packsSnapshot.connectionState == ConnectionState.waiting) {
                  return Text(
                    '불러오는 중...',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }

                final packs = packsSnapshot.data ?? const <AdminStoryPack>[];
                if (packs.isEmpty) {
                  return Text(
                    '등록된 스토리팩이 없어요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }

                final authorIds = <String>{
                  for (final pack in packs)
                    if (pack.authorId.isNotEmpty) pack.authorId,
                };

                return FutureBuilder<List<UserProfile>>(
                  future: _authorProfilesFor(authorIds),
                  builder: (context, authorsSnapshot) {
                    final liveNameByUid = {
                      for (final author
                          in authorsSnapshot.data ?? const <UserProfile>[])
                        author.uid: author.displayName,
                    };

                    // 이름 판정 우선순위: 지금 시점의 실제 프로필 이름 →
                    // 생성 시점 스냅샷(pack.authorName) → 안내 문구. UID는
                    // 이 화면 어디에도 문자열로 그대로 노출하지 않는다(검색
                    // 대상으로만 쓴다).
                    String resolveAuthorName(AdminStoryPack pack) {
                      final live = liveNameByUid[pack.authorId];
                      if (live != null && live.isNotEmpty) return live;
                      if (pack.authorName.isNotEmpty) return pack.authorName;
                      return '(작가 정보 없음)';
                    }

                    final filtered = _applyFilter(
                      packs,
                      query: _query,
                      range: _range,
                      from: _from,
                      to: _to,
                      resolveAuthorName: resolveAuthorName,
                    );
                    if (filtered.isEmpty) {
                      return Text(
                        '조건에 해당하는 작품이 없어요.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AdminColors.muted,
                        ),
                      );
                    }

                    final groups = _groupByAuthor(filtered, resolveAuthorName);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final group in groups) ...[
                          _AuthorGroupHeader(
                            authorName: group.authorName,
                            count: group.packs.length,
                          ),
                          for (final pack in group.packs)
                            _PackRow(
                              pack: pack,
                              authorName: group.authorName,
                              processing: _processingKeys.contains(pack.id),
                              onTakedown: () => _handleTakedown(pack),
                              onRestore: () => _handleRestore(pack),
                            ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorGroup {
  final String authorId;
  final String authorName;
  final List<AdminStoryPack> packs;

  const _AuthorGroup({
    required this.authorId,
    required this.authorName,
    required this.packs,
  });

  /// 이 작가의 팩 중 가장 최근 `createdAt` — 전부 null(백필 안 된 옛 팩만
  /// 있는 작가)이면 null.
  DateTime? get latestCreatedAt {
    DateTime? latest;
    for (final pack in packs) {
      final at = pack.createdAt;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }
}

/// [packs]에 검색어/기간 필터를 적용한다. 검색어는 (해석된) 작가 이름과
/// authorId(원본 UID) 양쪽에 걸린다 — 화면에는 UID를 절대 안 보여주지만,
/// UID를 알고 찾아온 운영자를 위해 검색 대상에는 넣는다.
List<AdminStoryPack> _applyFilter(
  List<AdminStoryPack> packs, {
  required String query,
  required ApprovalDateRange range,
  required DateTime? from,
  required DateTime? to,
  required String Function(AdminStoryPack) resolveAuthorName,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final weekAgo = startOfToday.subtract(const Duration(days: 6));

  bool matchesQuery(AdminStoryPack pack) {
    if (normalizedQuery.isEmpty) return true;
    final haystack = [
      resolveAuthorName(pack),
      pack.authorId,
    ].join(' ').toLowerCase();
    return haystack.contains(normalizedQuery);
  }

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

  return packs
      .where((pack) => matchesQuery(pack) && matchesDate(pack.createdAt))
      .toList();
}

/// authorId별로 묶는다. 그룹은 "가장 최근 활동"(팩 중 가장 늦은 createdAt)
/// 이 있는 작가가 먼저 오도록 정렬하고, createdAt을 전혀 모르는(옛 팩만
/// 있는) 작가는 맨 뒤로 밀린 뒤 이름 순으로 정렬한다.
List<_AuthorGroup> _groupByAuthor(
  List<AdminStoryPack> packs,
  String Function(AdminStoryPack) resolveAuthorName,
) {
  final order = <String>[];
  final buckets = <String, List<AdminStoryPack>>{};
  final names = <String, String>{};

  for (final pack in packs) {
    final list = buckets.putIfAbsent(pack.authorId, () {
      order.add(pack.authorId);
      return <AdminStoryPack>[];
    });
    names[pack.authorId] = resolveAuthorName(pack);
    list.add(pack);
  }

  final groups = [
    for (final authorId in order)
      _AuthorGroup(
        authorId: authorId,
        authorName: names[authorId]!,
        packs: buckets[authorId]!,
      ),
  ];

  groups.sort((a, b) {
    final x = a.latestCreatedAt;
    final y = b.latestCreatedAt;
    if (x == null && y == null) return a.authorName.compareTo(b.authorName);
    if (x == null) return 1;
    if (y == null) return -1;
    final byDate = y.compareTo(x); // 최신이 먼저.
    return byDate != 0 ? byDate : a.authorName.compareTo(b.authorName);
  });
  return groups;
}

class _FilterBar extends StatelessWidget {
  final String query;
  final ApprovalDateRange range;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<ApprovalDateRange> onRangeChanged;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;

  const _FilterBar({
    required this.query,
    required this.range,
    required this.from,
    required this.to,
    required this.onQueryChanged,
    required this.onRangeChanged,
    required this.onPickFrom,
    required this.onPickTo,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                onChanged: onQueryChanged,
                style: TextStyle(fontSize: 12, color: AdminColors.ivory),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  hintText: '작가 이름 · 작가 UID 검색',
                  hintStyle: TextStyle(fontSize: 12, color: AdminColors.muted),
                  filled: true,
                  fillColor: AdminColors.panel,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AdminColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AdminColors.gold),
                  ),
                ),
              ),
            ),
            for (final option in ApprovalDateRange.values)
              _Chip(
                label: option.label,
                selected: range == option,
                onTap: () => onRangeChanged(option),
              ),
          ],
        ),
        if (range == ApprovalDateRange.custom) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _DateButton(
                label: from == null ? '시작일' : formatRequestedDate(from),
                onTap: onPickFrom,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '—',
                  style: TextStyle(fontSize: 12, color: AdminColors.muted),
                ),
              ),
              _DateButton(
                label: to == null ? '종료일' : formatRequestedDate(to),
                onTap: onPickTo,
              ),
              const SizedBox(width: 10),
              Text(
                '생성일 기준',
                style: TextStyle(fontSize: 11, color: AdminColors.muted),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AdminColors.gold : Colors.transparent,
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? Colors.white : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DateButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AdminColors.panel,
          border: Border.all(color: AdminColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: AdminColors.ivory),
        ),
      ),
    );
  }
}

class _AuthorGroupHeader extends StatelessWidget {
  final String authorName;
  final int count;

  const _AuthorGroupHeader({required this.authorName, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            authorName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AdminColors.ivory,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AdminColors.badgeBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AdminColors.statusDraftText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackRow extends StatelessWidget {
  final AdminStoryPack pack;
  final String authorName;
  final bool processing;
  final VoidCallback onTakedown;
  final VoidCallback onRestore;

  const _PackRow({
    required this.pack,
    required this.authorName,
    required this.processing,
    required this.onTakedown,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            pack.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AdminColors.ivory,
                            ),
                          ),
                        ),
                        if (pack.suspended) ...[
                          const SizedBox(width: 8),
                          const _SuspendedBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '작가: $authorName'
                      '${pack.genres.isNotEmpty ? ' · ${pack.genres.join(', ')}' : ''}'
                      '${pack.createdAt != null ? ' · ${formatRequestedDate(pack.createdAt)} 생성' : ''}',
                      style: TextStyle(fontSize: 11, color: AdminColors.muted),
                    ),
                    if (pack.suspended && pack.suspendedReason != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '내려짐 사유: ${pack.suspendedReason}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.dirtyBannerText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AdminColors.panel2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  pack.type == StoryPackType.interactive ? '인터랙티브' : '선형',
                  style: TextStyle(fontSize: 12, color: AdminColors.ivory),
                ),
              ),
            ],
          ),
          if (pack.canForceTakedown || pack.canRestore) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: pack.canRestore
                  ? ApprovalActionButton(
                      label: '복원',
                      bg: AdminColors.approveBg,
                      fg: AdminColors.approveText,
                      border: AdminColors.approveBorder,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      fontSize: 12,
                      onTap: processing ? null : onRestore,
                    )
                  : ApprovalActionButton(
                      label: '강제 내리기',
                      bg: AdminColors.rejectBg,
                      fg: AdminColors.rejectText,
                      border: AdminColors.rejectBorder,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      fontSize: 12,
                      onTap: processing ? null : onTakedown,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "내려짐" 배지 — status_tag.dart의 파스텔 bg + 진한 텍스트 배지 관례를
/// 따르되, activity_event.dart의 제재 조치 계열과 같은 색(dirtyBannerBg/
/// Text, 팔레트의 유일한 앰버 톤)을 쓴다 — 승인/반려도 아닌 별도 종류의
/// 상태라는 걸 색으로도 구분한다.
class _SuspendedBadge extends StatelessWidget {
  const _SuspendedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AdminColors.dirtyBannerBg,
        border: Border.all(color: AdminColors.dirtyBannerBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '내려짐',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AdminColors.dirtyBannerText,
        ),
      ),
    );
  }
}
