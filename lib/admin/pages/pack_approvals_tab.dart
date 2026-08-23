import 'package:flutter/material.dart';

import '../data/activity_log_repository.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../models/activity_event.dart';
import '../models/admin_image.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_story_pack.dart';
import '../widgets/admin_theme.dart';
import 'approvals/approval_filter.dart'
    show ApprovalStatusFilter, applyHistoryFilter, formatWaitedLabel;
import 'approvals/history_detail_pane.dart';
import 'approvals/node_diff_view.dart' show promptRejectionReason;
import 'pack_approvals/pack_approval_filter.dart';
import 'pack_approvals/pack_approvals_filter_bar.dart';
import 'pack_approvals/pack_pending_detail_pane.dart';
import 'pack_approvals/pack_pending_list_pane.dart';

/// "스토리팩 승인" — admin 전용. 팩 단위의 두 승인 요청을 검토한다: 신규
/// 연재 요청(serializationStatus == pending)과 메타데이터 수정 요청
/// (pendingMetadataAction == 'edit'). 개별 노드 콘텐츠 승인(ApprovalsTab)과는
/// 완전히 별개의 검토 대상이지만, 둘 다 "AdminStoryPack 문서 하나를 검토하는"
/// 같은 리뷰어 워크플로라 여기 한 화면에 묶는다.
///
/// 승인 대기함(ApprovalsTab)과 같은 목록(왼쪽) + 상세(오른쪽) 2단 구조다 —
/// pack_approvals/ 아래 패턴은 approvals/의 것을 그대로 따른다(필터/정렬은
/// 순수 로직으로 분리, 목록·상세 위젯은 프레젠테이션 전담).
class PackApprovalsTab extends StatefulWidget {
  final AdminStoryRepository repository;
  final AdminImageRepository imageRepository;
  final String reviewerUid;

  /// 승인/반려를 개요의 "최근 활동"에 남기고, "처리됨"/"전체" 상태에서
  /// 처리 이력을 읽어온다. null이면 기록도, 이력 조회도 하지 않는다.
  final ActivityLogRepository? activityLog;

  /// packId → 작품 제목/작가 이름 — 전체 스토리팩 목록 기준(대기 중인 것만이
  /// 아니라)이다. 처리 이력에 뜨는 팩은 이미 승인/반려가 끝나 대기 목록에서
  /// 빠진 것들이라, 대기 스트림만으로 만든 맵으로는 검색/표시가 안 된다.
  final Map<String, String> packTitles;
  final Map<String, String> packAuthors;

  const PackApprovalsTab({
    super.key,
    required this.repository,
    required this.imageRepository,
    required this.reviewerUid,
    required this.packTitles,
    required this.packAuthors,
    this.activityLog,
  });

  @override
  State<PackApprovalsTab> createState() => _PackApprovalsTabState();
}

class _PackApprovalsTabState extends State<PackApprovalsTab> {
  /// State에 한 번만 만든다 — build()에서 매번 새로 구독하면 부모가 재빌드될
  /// 때마다 목록이 나타났다 사라진다(ApprovalsTab에서 반복해 겪은 문제).
  late final Stream<List<AdminStoryPack>> _pendingSerializationStream = widget
      .repository
      .watchPendingSerializationRequests();
  late final Stream<List<AdminStoryPack>> _pendingMetadataStream = widget
      .repository
      .watchPendingMetadataEdits();
  late final Stream<List<AdminImage>> _imagesStream = widget.imageRepository
      .watchImages();

  /// "처리됨"/"전체" 상태에서만 쓰인다 — 연재 시작/메타데이터 변경 승인·반려
  /// 네 가지 kind를 전부 묶어서 하나의 이력으로 보여준다(요청 사양 화면에는
  /// 유형 구분이 배지로만 남고, 별도 스트림으로 쪼개지 않는다).
  late final Stream<List<ActivityEvent>> _historyStream =
      widget.activityLog?.watchApprovalHistory(
        kinds: const [
          ActivityKind.packSerializationApproved,
          ActivityKind.packSerializationRejected,
          ActivityKind.packMetadataApproved,
          ActivityKind.packMetadataRejected,
          // 강제 내리기/복원(all_story_packs_section.dart)도 팩 단위 조치라
          // 여기 같이 묶는다 — 별도 화면을 새로 만들지 않고 이미 있는
          // "스토리팩 승인" 처리 이력에 얹는다. applyHistoryFilter는 kind로
          // 걸러내지 않으므로(검색/기간만) 유형 필터(연재 시작/정보 변경)와도
          // 안 얽힌다.
          ActivityKind.packSuspended,
          ActivityKind.packRestored,
        ],
      ) ??
      Stream.value(const <ActivityEvent>[]);

  String _titleOf(String packId) => widget.packTitles[packId] ?? packId;

  /// 발행된 노드 개수(연재 시작 요청 상세)용 — 선택한 팩이 바뀔 때마다 새로
  /// 구독하지 않도록 팩 id별로 캐시해 둔다.
  final Map<String, Stream<List<AdminStoryNodeSummary>>> _nodeSummaryStreams =
      {};

  Stream<List<AdminStoryNodeSummary>> _nodeSummariesFor(String packId) {
    return _nodeSummaryStreams.putIfAbsent(
      packId,
      () => widget.repository.watchNodeSummaries(packId),
    );
  }

  PackApprovalFilter _filter = const PackApprovalFilter();
  String? _selectedKey;
  final Set<String> _processingKeys = {};

  Future<void> _log({
    required AdminStoryPack pack,
    required ActivityKind kind,
    required String action,
  }) async {
    final log = widget.activityLog;
    if (log == null) return;
    await log.log(
      kind: kind,
      actorUid: widget.reviewerUid,
      message:
          '${pack.authorName.isEmpty ? '(작가 이름 없음)' : pack.authorName} · '
          '「${pack.title}」 $action',
      packId: pack.id,
      authorName: pack.authorName,
    );
  }

  Future<void> _approve(PendingPackRequest request) async {
    final key = request.key;
    if (_processingKeys.contains(key)) return;
    setState(() => _processingKeys.add(key));
    try {
      if (request.kind == PackRequestKind.serialization) {
        await widget.repository.approveSerialization(
          request.pack,
          reviewerUid: widget.reviewerUid,
        );
        await _log(
          pack: request.pack,
          kind: ActivityKind.packSerializationApproved,
          action: '연재 시작 승인',
        );
      } else {
        await widget.repository.approveMetadataEdit(
          request.pack,
          reviewerUid: widget.reviewerUid,
        );
        await _log(
          pack: request.pack,
          kind: ActivityKind.packMetadataApproved,
          action: '작품정보 변경 승인',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('승인에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _processingKeys.remove(key));
    }
  }

  Future<void> _reject(PendingPackRequest request) async {
    final reason = await promptRejectionReason(context);
    if (reason == null || !mounted) return;

    final key = request.key;
    setState(() => _processingKeys.add(key));
    try {
      if (request.kind == PackRequestKind.serialization) {
        await widget.repository.rejectSerialization(
          request.pack,
          reviewerUid: widget.reviewerUid,
          reason: reason,
        );
        await _log(
          pack: request.pack,
          kind: ActivityKind.packSerializationRejected,
          action: '연재 시작 반려',
        );
      } else {
        await widget.repository.rejectMetadataEdit(
          request.pack,
          reviewerUid: widget.reviewerUid,
          reason: reason,
        );
        await _log(
          pack: request.pack,
          kind: ActivityKind.packMetadataRejected,
          action: '작품정보 변경 반려',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('반려에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _processingKeys.remove(key));
    }
  }

  String _summary(List<PendingPackRequest> requests) {
    if (requests.isEmpty) return '대기 중인 요청이 없어요.';
    DateTime? oldest;
    for (final request in requests) {
      final at = request.requestedAt;
      if (at == null) continue;
      if (oldest == null || at.isBefore(oldest)) oldest = at;
    }
    final waited = oldest == null
        ? ''
        : ' · 가장 오래 기다린 요청 ${formatWaitedLabel(oldest)}';
    return '${requests.length}건 대기$waited';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminImage>>(
      stream: _imagesStream,
      builder: (context, imageSnapshot) {
        final imagesById = {
          for (final img in imageSnapshot.data ?? const <AdminImage>[])
            img.id: img,
        };

        return StreamBuilder<List<AdminStoryPack>>(
          stream: _pendingSerializationStream,
          builder: (context, serializationSnapshot) {
            if (serializationSnapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  '연재 시작 요청을 불러오지 못했어요: ${serializationSnapshot.error}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.danger,
                  ),
                ),
              );
            }

            return StreamBuilder<List<AdminStoryPack>>(
              stream: _pendingMetadataStream,
              builder: (context, metadataSnapshot) {
                if (metadataSnapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: SelectableText(
                      '메타데이터 변경 요청을 불러오지 못했어요: ${metadataSnapshot.error}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.danger,
                      ),
                    ),
                  );
                }

                final serializationPacks =
                    serializationSnapshot.data ?? const <AdminStoryPack>[];
                final metadataPacks =
                    metadataSnapshot.data ?? const <AdminStoryPack>[];

                final all = [
                  for (final pack in serializationPacks)
                    PendingPackRequest(
                      pack: pack,
                      kind: PackRequestKind.serialization,
                    ),
                  for (final pack in metadataPacks)
                    PendingPackRequest(
                      pack: pack,
                      kind: PackRequestKind.metadataEdit,
                    ),
                ];

                // 상태 필터가 "처리됨"이면 대기 목록 자체를 비운다 — 목록
                // 왼쪽엔 이력만 보인다. "전체"는 둘 다, "대기중"(기본)은
                // 대기만(approvals_tab.dart와 같은 규칙).
                final showPending =
                    _filter.status != ApprovalStatusFilter.handled;
                final showHistory =
                    _filter.status != ApprovalStatusFilter.pending;

                final visible = showPending
                    ? applyPackApprovalFilter(all, _filter)
                    : const <PendingPackRequest>[];

                return StreamBuilder<List<ActivityEvent>>(
                  stream: _historyStream,
                  builder: (context, historySnapshot) {
                    final historyEvents =
                        historySnapshot.data ?? const <ActivityEvent>[];
                    final visibleHistory = showHistory
                        ? applyHistoryFilter(
                            historyEvents,
                            query: _filter.query,
                            range: _filter.range,
                            from: _filter.from,
                            to: _filter.to,
                            sort: _filter.sort,
                            packTitles: widget.packTitles,
                            packAuthors: widget.packAuthors,
                          )
                        : const <ActivityEvent>[];

                    // 대기 목록 뒤에 이력이 이어 붙는 순서 그대로 하나의 키
                    // 목록을 만든다 — PackPendingListPane이 그리는 순서와
                    // 같아야 이전/다음 이동이 화면과 어긋나지 않는다.
                    final combinedKeys = [
                      for (final request in visible) request.key,
                      for (final event in visibleHistory)
                        PackPendingListPane.historyKeyFor(event),
                    ];

                    var index = _selectedKey == null
                        ? -1
                        : combinedKeys.indexOf(_selectedKey!);
                    if (index == -1 && combinedKeys.isNotEmpty) index = 0;

                    PendingPackRequest? selected;
                    ActivityEvent? selectedHistory;
                    if (index >= 0) {
                      if (index < visible.length) {
                        selected = visible[index];
                      } else {
                        selectedHistory =
                            visibleHistory[index - visible.length];
                      }
                    }

                    final selectedKey = index >= 0 ? combinedKeys[index] : null;

                    void goTo(int target) {
                      setState(() => _selectedKey = combinedKeys[target]);
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PackApprovalsFilterBar(
                          filter: _filter,
                          summary: _summary(all),
                          onChanged: (next) => setState(() => _filter = next),
                        ),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 290,
                                  maxWidth: 400,
                                ),
                                child: SizedBox(
                                  width: 360,
                                  child: PackPendingListPane(
                                    requests: visible,
                                    selectedKey: selectedKey,
                                    onSelect: (request) => setState(
                                      () => _selectedKey = request.key,
                                    ),
                                    historyEntries: visibleHistory,
                                    selectedHistoryKey: selectedHistory == null
                                        ? null
                                        : selectedKey,
                                    onSelectHistory: (event) => setState(
                                      () => _selectedKey =
                                          PackPendingListPane.historyKeyFor(
                                            event,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: selectedHistory != null
                                    ? HistoryDetailPane(
                                        event: selectedHistory,
                                        packTitle:
                                            selectedHistory.packId == null
                                            ? ''
                                            : _titleOf(selectedHistory.packId!),
                                        index: index,
                                        total: combinedKeys.length,
                                        onPrev: index > 0
                                            ? () => goTo(index - 1)
                                            : null,
                                        onNext: index < combinedKeys.length - 1
                                            ? () => goTo(index + 1)
                                            : null,
                                      )
                                    : PackPendingDetailPane(
                                        request: selected,
                                        imagesById: imagesById,
                                        nodeSummariesStream:
                                            selected == null ||
                                                selected.kind !=
                                                    PackRequestKind
                                                        .serialization
                                            ? null
                                            : _nodeSummariesFor(
                                                selected.pack.id,
                                              ),
                                        processing:
                                            selectedKey != null &&
                                            _processingKeys.contains(
                                              selectedKey,
                                            ),
                                        index: index,
                                        total: combinedKeys.length,
                                        onApprove: selected == null
                                            ? () {}
                                            : () => _approve(selected!),
                                        onReject: selected == null
                                            ? () {}
                                            : () => _reject(selected!),
                                        onPrev: index > 0
                                            ? () => goTo(index - 1)
                                            : null,
                                        onNext:
                                            index >= 0 &&
                                                index < combinedKeys.length - 1
                                            ? () => goTo(index + 1)
                                            : null,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
