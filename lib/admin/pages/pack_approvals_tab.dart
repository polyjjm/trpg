import 'package:flutter/material.dart';

import '../data/admin_story_repository.dart';
import '../models/admin_story_pack.dart';
import '../widgets/admin_theme.dart';

/// "스토리팩 승인" — admin 전용. 팩 단위의 두 승인 요청을 검토한다: 신규
/// 연재 요청(serializationStatus == pending)과 메타데이터 수정 요청
/// (pendingMetadataAction == 'edit'). 개별 노드 콘텐츠 승인(ApprovalsTab)과는
/// 완전히 별개의 검토 대상이지만, 둘 다 "AdminStoryPack 문서 하나를 검토하는"
/// 같은 리뷰어 워크플로라 여기 한 화면에 묶는다.
class PackApprovalsTab extends StatefulWidget {
  final AdminStoryRepository repository;
  final String reviewerUid;

  const PackApprovalsTab({
    super.key,
    required this.repository,
    required this.reviewerUid,
  });

  @override
  State<PackApprovalsTab> createState() => _PackApprovalsTabState();
}

class _PackApprovalsTabState extends State<PackApprovalsTab> {
  late final Stream<List<AdminStoryPack>> _pendingSerializationStream = widget
      .repository
      .watchPendingSerializationRequests();
  late final Stream<List<AdminStoryPack>> _pendingMetadataStream = widget
      .repository
      .watchPendingMetadataEdits();

  Future<void> _handleRejectSerialization(
    BuildContext context,
    AdminStoryPack pack,
  ) async {
    final reason = await _promptRejectionReason(
      context,
      title: '연재 시작 반려 사유 (선택)',
    );
    if (reason == null) return;
    await widget.repository.rejectSerialization(
      pack,
      reviewerUid: widget.reviewerUid,
      reason: reason.isEmpty ? null : reason,
    );
  }

  Future<void> _handleRejectMetadataEdit(
    BuildContext context,
    AdminStoryPack pack,
  ) async {
    final reason = await _promptRejectionReason(
      context,
      title: '메타데이터 변경 반려 사유 (선택)',
    );
    if (reason == null) return;
    await widget.repository.rejectMetadataEdit(
      pack,
      reviewerUid: widget.reviewerUid,
      reason: reason.isEmpty ? null : reason,
    );
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
              '스토리팩 승인',
              style: TextStyle(
                fontSize: 16,
                color: AdminColors.ivory,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '팩이 독자 라이브러리에 노출되려면 먼저 "연재 시작 승인"을 받아야 해요. 승인 후에는 제목/장르/설명/표지 '
              '같은 메타데이터를 바꿀 때마다 "메타데이터 수정 승인"을 따로 받아요 — 노드 콘텐츠 승인(승인 대기함)과는 별개예요.',
              style: TextStyle(
                fontSize: 12,
                color: AdminColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '신규 연재 요청',
              style: TextStyle(
                fontSize: 14,
                color: AdminColors.ivory,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            StreamBuilder<List<AdminStoryPack>>(
              stream: _pendingSerializationStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SelectableText(
                    '목록을 불러오지 못했어요: ${snapshot.error}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.danger,
                    ),
                  );
                }
                final packs = snapshot.data ?? const <AdminStoryPack>[];
                if (packs.isEmpty) {
                  return Text(
                    '대기 중인 연재 시작 요청이 없어요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }
                return Column(
                  children: [
                    for (final pack in packs)
                      _PackRequestCard(
                        pack: pack,
                        kind: _RequestKind.serialization,
                        onApprove: () => widget.repository.approveSerialization(
                          pack,
                          reviewerUid: widget.reviewerUid,
                        ),
                        onReject: () =>
                            _handleRejectSerialization(context, pack),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Text(
              '메타데이터 수정 요청',
              style: TextStyle(
                fontSize: 14,
                color: AdminColors.ivory,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            StreamBuilder<List<AdminStoryPack>>(
              stream: _pendingMetadataStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SelectableText(
                    '목록을 불러오지 못했어요: ${snapshot.error}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.danger,
                    ),
                  );
                }
                final packs = snapshot.data ?? const <AdminStoryPack>[];
                if (packs.isEmpty) {
                  return Text(
                    '대기 중인 메타데이터 수정 요청이 없어요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted),
                  );
                }
                return Column(
                  children: [
                    for (final pack in packs)
                      _PackRequestCard(
                        pack: pack,
                        kind: _RequestKind.metadata,
                        onApprove: () => widget.repository.approveMetadataEdit(
                          pack,
                          reviewerUid: widget.reviewerUid,
                        ),
                        onReject: () =>
                            _handleRejectMetadataEdit(context, pack),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _RequestKind { serialization, metadata }

class _PackRequestCard extends StatelessWidget {
  final AdminStoryPack pack;
  final _RequestKind kind;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PackRequestCard({
    required this.pack,
    required this.kind,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final submittedAt = kind == _RequestKind.serialization
        ? pack.serializationSubmittedAt
        : pack.metadataSubmittedAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    Text(
                      pack.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AdminColors.ivory,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pack.authorName.isEmpty ? '(작가 이름 없음)' : pack.authorName,
                      style: TextStyle(fontSize: 12, color: AdminColors.muted),
                    ),
                    if (submittedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${_formatDate(submittedAt)} 제출',
                        style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _ActionButton(
                label: '승인',
                bg: AdminColors.approveBg,
                fg: AdminColors.approveText,
                border: AdminColors.approveBorder,
                onTap: onApprove,
              ),
              const SizedBox(width: 8),
              _ActionButton(
                label: '반려',
                bg: AdminColors.rejectBg,
                fg: AdminColors.rejectText,
                border: AdminColors.rejectBorder,
                onTap: onReject,
              ),
            ],
          ),
          if (pack.genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final g in pack.genres) _GenreTag(g)],
            ),
          ],
          if (pack.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              pack.description,
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.ivory,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GenreTag extends StatelessWidget {
  final String slug;

  const _GenreTag(this.slug);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AdminColors.panel2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        slug,
        style: TextStyle(fontSize: 11, color: AdminColors.muted),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color border;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: fg)),
      ),
    );
  }
}

Future<String?> _promptRejectionReason(
  BuildContext context, {
  required String title,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AdminColors.panel,
      title: Text(title, style: TextStyle(color: AdminColors.ivory)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        style: TextStyle(color: AdminColors.ivory),
        decoration: InputDecoration(
          hintText: '작가에게 보여줄 사유를 적어주세요. 비워두면 사유 없이 반려돼요.',
          hintStyle: TextStyle(color: AdminColors.muted, fontSize: 12),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AdminColors.border),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AdminColors.gold),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('취소', style: TextStyle(color: AdminColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text(
            '반려하기',
            style: TextStyle(color: AdminColors.rejectText),
          ),
        ),
      ],
    ),
  );
}

String _formatDate(DateTime dt) =>
    '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
