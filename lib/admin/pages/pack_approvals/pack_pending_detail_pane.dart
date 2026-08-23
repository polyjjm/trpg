import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../models/admin_image.dart';
import '../../models/admin_story_node_summary.dart';
import '../../models/admin_story_pack.dart';
import '../../models/node_status.dart';
import '../../widgets/admin_theme.dart';
import '../approvals/approval_filter.dart'
    show formatRequestedDate, formatWaitedLabel;
import '../approvals/node_diff_view.dart'
    show ApprovalActionButton, BackgroundImageDiff, DiffSectionLabel;
import 'pack_approval_filter.dart';

/// 스토리팩 승인 화면 오른쪽 상세 — 연재 시작 요청이면 팩의 현재 스냅샷
/// (표지·가격·발행 노드 개수 등)을, 메타데이터 변경 요청이면 liveMetadata
/// (마지막 승인본) vs draft의 필드별 before/after 비교를 보여준다.
///
/// 하단에 이전/다음이 있어서 승인 대기함(PendingDetailPane)과 같은 방식으로
/// 연속 처리할 수 있다.
class PackPendingDetailPane extends StatelessWidget {
  final PendingPackRequest? request;
  final Map<String, AdminImage> imagesById;

  /// 연재 시작 요청일 때만 쓴다 — 발행된 노드 개수 계산용. 팩 id별로
  /// 호출부에서 캐시해서 넘긴다(매 build마다 새로 구독하면 목록이 깜빡인다).
  final Stream<List<AdminStoryNodeSummary>>? nodeSummariesStream;

  final bool processing;
  final int index;
  final int total;

  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const PackPendingDetailPane({
    super.key,
    required this.request,
    required this.imagesById,
    required this.nodeSummariesStream,
    required this.processing,
    required this.index,
    required this.total,
    required this.onApprove,
    required this.onReject,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final current = request;
    if (current == null) {
      return Center(
        child: Text(
          '왼쪽에서 요청을 선택하세요.',
          style: TextStyle(fontSize: 13, color: AdminColors.muted),
        ),
      );
    }

    final pack = current.pack;
    final isSerialization = current.kind == PackRequestKind.serialization;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSerialization
                      ? AdminColors.statusPendingBg
                      : AdminColors.imageCategoryBackgroundBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  current.kind.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isSerialization
                        ? AdminColors.statusPendingText
                        : AdminColors.imageCategoryBackgroundText,
                  ),
                ),
              ),
              Text(
                pack.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.ivory,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${pack.authorName.isEmpty ? '(작가 이름 없음)' : pack.authorName} · '
            '${formatRequestedDate(current.requestedAt)} 요청'
            '${current.requestedAt == null ? '' : ' (${formatWaitedLabel(current.requestedAt)} 대기)'}',
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
          const SizedBox(height: 20),
          if (isSerialization)
            _SerializationDetail(
              pack: pack,
              imagesById: imagesById,
              nodeSummariesStream: nodeSummariesStream,
            )
          else
            _MetadataDiffDetail(pack: pack, imagesById: imagesById),
          const SizedBox(height: 26),
          Row(
            children: [
              ApprovalActionButton(
                label: '승인',
                bg: AdminColors.approveBg,
                fg: AdminColors.approveText,
                border: AdminColors.approveBorder,
                onTap: processing ? null : onApprove,
              ),
              const SizedBox(width: 10),
              ApprovalActionButton(
                label: '반려',
                bg: AdminColors.rejectBg,
                fg: AdminColors.rejectText,
                border: AdminColors.rejectBorder,
                onTap: processing ? null : onReject,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.only(top: 18),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AdminColors.border)),
            ),
            child: Row(
              children: [
                Text(
                  '${index + 1} / $total',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
                const Spacer(),
                _NavButton(label: '← 이전', onTap: onPrev),
                const SizedBox(width: 8),
                _NavButton(label: '다음 →', onTap: onNext),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SerializationDetail extends StatelessWidget {
  final AdminStoryPack pack;
  final Map<String, AdminImage> imagesById;
  final Stream<List<AdminStoryNodeSummary>>? nodeSummariesStream;

  const _SerializationDetail({
    required this.pack,
    required this.imagesById,
    required this.nodeSummariesStream,
  });

  @override
  Widget build(BuildContext context) {
    final cover = pack.coverImageId == null
        ? null
        : imagesById[pack.coverImageId];
    final background = pack.defaultBackgroundImage == null
        ? null
        : imagesById[pack.defaultBackgroundImage];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DiffSectionLabel('표지'),
        const SizedBox(height: 6),
        _Thumb(image: cover),
        const SizedBox(height: 18),
        if (pack.genres.isNotEmpty) ...[
          const DiffSectionLabel('장르'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final g in pack.genres) _Tag(g)],
          ),
          const SizedBox(height: 18),
        ],
        if (pack.description.isNotEmpty) ...[
          const DiffSectionLabel('설명'),
          const SizedBox(height: 6),
          Text(
            pack.description,
            style: TextStyle(
              fontSize: 13,
              color: AdminColors.ivory,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
        ],
        const DiffSectionLabel('가격'),
        const SizedBox(height: 6),
        Text(
          pack.salePrice != null
              ? '${formatWon(pack.price)} → ${formatWon(pack.salePrice!)}'
                    '${_formatDiscountWindow(pack.discountStartAt, pack.discountEndAt)}'
              : formatWon(pack.price),
          style: TextStyle(
            fontSize: 13,
            color: pack.salePrice != null
                ? AdminColors.gold
                : AdminColors.ivory,
          ),
        ),
        const SizedBox(height: 18),
        const DiffSectionLabel('기본 배경'),
        const SizedBox(height: 6),
        _Thumb(image: background),
        const SizedBox(height: 18),
        const DiffSectionLabel('기본 BGM / TTS 보이스'),
        const SizedBox(height: 6),
        Text(
          'BGM: ${pack.defaultBgmId ?? '(없음)'}   ·   '
          'TTS: ${pack.defaultTtsVoiceId ?? '(없음)'}',
          style: TextStyle(fontSize: 13, color: AdminColors.ivory),
        ),
        const SizedBox(height: 18),
        const DiffSectionLabel('발행된 노드 개수'),
        const SizedBox(height: 6),
        _PublishedNodeCount(stream: nodeSummariesStream),
      ],
    );
  }
}

class _PublishedNodeCount extends StatelessWidget {
  final Stream<List<AdminStoryNodeSummary>>? stream;

  const _PublishedNodeCount({required this.stream});

  @override
  Widget build(BuildContext context) {
    final source = stream;
    if (source == null) {
      return Text(
        '알 수 없음',
        style: TextStyle(fontSize: 13, color: AdminColors.muted),
      );
    }
    return StreamBuilder<List<AdminStoryNodeSummary>>(
      stream: source,
      builder: (context, snapshot) {
        final nodes = snapshot.data;
        if (nodes == null) {
          return Text(
            '불러오는 중…',
            style: TextStyle(fontSize: 13, color: AdminColors.muted),
          );
        }
        final published = nodes
            .where((n) => n.status == NodeStatus.published)
            .length;
        return Text(
          '$published개 (전체 ${nodes.length}개 중)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: published > 0 ? AdminColors.ivory : AdminColors.danger,
          ),
        );
      },
    );
  }
}

/// liveMetadata(마지막 승인본) vs 현재 draft 값을 필드별로 비교해, 실제로
/// 달라진 필드만 보여준다 — 다 보여주면 뭐가 바뀐 건지 오히려 안 보인다.
class _MetadataDiffDetail extends StatelessWidget {
  final AdminStoryPack pack;
  final Map<String, AdminImage> imagesById;

  const _MetadataDiffDetail({required this.pack, required this.imagesById});

  @override
  Widget build(BuildContext context) {
    final live = pack.liveMetadata ?? const <String, dynamic>{};

    final liveTitle = live['title'] as String? ?? '';
    final liveGenres =
        (live['genres'] as List<dynamic>?)?.cast<String>() ?? const <String>[];
    final liveDescription = live['description'] as String? ?? '';
    final liveCoverImageId = live['coverImageId'] as String?;
    final livePrice = (live['price'] as num?)?.toInt() ?? 0;
    final liveSalePrice = (live['salePrice'] as num?)?.toInt();
    final liveDiscountStart = (live['discountStartAt'] as Timestamp?)?.toDate();
    final liveDiscountEnd = (live['discountEndAt'] as Timestamp?)?.toDate();
    final liveBgmId = live['defaultBgmId'] as String?;
    final liveTtsVoiceId = live['defaultTtsVoiceId'] as String?;

    final rows = <Widget>[];

    if (liveTitle != pack.title) {
      rows.add(_TextDiffRow(label: '제목', before: liveTitle, after: pack.title));
    }
    if (!listEquals(liveGenres, pack.genres)) {
      rows.add(
        _TextDiffRow(
          label: '장르',
          before: liveGenres.isEmpty ? '(없음)' : liveGenres.join(', '),
          after: pack.genres.isEmpty ? '(없음)' : pack.genres.join(', '),
        ),
      );
    }
    if (liveDescription != pack.description) {
      rows.add(
        _TextDiffRow(
          label: '설명',
          before: liveDescription.isEmpty ? '(없음)' : liveDescription,
          after: pack.description.isEmpty ? '(없음)' : pack.description,
        ),
      );
    }
    if (liveCoverImageId != pack.coverImageId) {
      rows.add(
        _ImageDiffRow(
          label: '표지',
          before: liveCoverImageId == null
              ? null
              : imagesById[liveCoverImageId],
          after: pack.coverImageId == null
              ? null
              : imagesById[pack.coverImageId],
        ),
      );
    }
    if (livePrice != pack.price || liveSalePrice != pack.salePrice) {
      rows.add(
        _TextDiffRow(
          label: '가격',
          before: liveSalePrice != null
              ? '${formatWon(livePrice)} → ${formatWon(liveSalePrice)}'
              : formatWon(livePrice),
          after: pack.salePrice != null
              ? '${formatWon(pack.price)} → ${formatWon(pack.salePrice!)}'
              : formatWon(pack.price),
        ),
      );
    }
    if (liveDiscountStart != pack.discountStartAt ||
        liveDiscountEnd != pack.discountEndAt) {
      rows.add(
        _TextDiffRow(
          label: '할인 기간',
          before:
              _formatDiscountWindow(
                liveDiscountStart,
                liveDiscountEnd,
              ).trim().isEmpty
              ? '(없음)'
              : _formatDiscountWindow(liveDiscountStart, liveDiscountEnd),
          after:
              _formatDiscountWindow(
                pack.discountStartAt,
                pack.discountEndAt,
              ).trim().isEmpty
              ? '(없음)'
              : _formatDiscountWindow(pack.discountStartAt, pack.discountEndAt),
        ),
      );
    }
    if (liveBgmId != pack.defaultBgmId) {
      rows.add(
        _TextDiffRow(
          label: '기본 BGM',
          before: liveBgmId ?? '(없음)',
          after: pack.defaultBgmId ?? '(없음)',
        ),
      );
    }
    if (liveTtsVoiceId != pack.defaultTtsVoiceId) {
      rows.add(
        _TextDiffRow(
          label: '기본 TTS 보이스',
          before: liveTtsVoiceId ?? '(없음)',
          after: pack.defaultTtsVoiceId ?? '(없음)',
        ),
      );
    }

    if (rows.isEmpty) {
      return Text(
        '승인된 값과 달라진 필드가 없어요.',
        style: TextStyle(fontSize: 13, color: AdminColors.muted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i != rows.length - 1) const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _TextDiffRow extends StatelessWidget {
  final String label;
  final String before;
  final String after;

  const _TextDiffRow({
    required this.label,
    required this.before,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DiffSectionLabel(label),
        const SizedBox(height: 6),
        Text(
          before,
          style: TextStyle(
            fontSize: 13,
            color: AdminColors.muted,
            decoration: TextDecoration.lineThrough,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          after,
          style: TextStyle(fontSize: 13, color: AdminColors.ivory, height: 1.5),
        ),
      ],
    );
  }
}

class _ImageDiffRow extends StatelessWidget {
  final String label;
  final AdminImage? before;
  final AdminImage? after;

  const _ImageDiffRow({
    required this.label,
    required this.before,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DiffSectionLabel(label),
        const SizedBox(height: 6),
        BackgroundImageDiff(beforeImage: before, afterImage: after),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  final AdminImage? image;

  const _Thumb({required this.image});

  @override
  Widget build(BuildContext context) {
    final url = image?.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 132,
        height: 80,
        color: AdminColors.panel2,
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.image_not_supported_outlined,
                  size: 18,
                  color: AdminColors.muted,
                ),
              )
            : Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 18,
                  color: AdminColors.muted,
                ),
              ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String slug;

  const _Tag(this.slug);

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

class _NavButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _NavButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: AdminColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            softWrap: false,
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
        ),
      ),
    );
  }
}

String _formatDiscountWindow(DateTime? start, DateTime? end) {
  if (start == null && end == null) return '';
  final startText = start == null ? '(없음)' : formatRequestedDate(start);
  final endText = end == null ? '(없음)' : formatRequestedDate(end);
  return ' ($startText ~ $endText)';
}
