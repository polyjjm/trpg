import 'dart:async';

import 'package:flutter/material.dart';

import '../data/home_event_dismissal_store.dart';
import '../models/home_event.dart';
import '../models/story_pack.dart';
import '../pages/story_pack_detail_page.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _amber = Color(0xFFFFB648);
const Color _panelBg = Color(0xFF0E0E0D);
const Color _panelBorder = Color(0xFF262624);
const Color _hairline = Color(0xFF1E1E1C);

/// 홈 탭이 열릴 때(패키지 스트림이 첫 데이터를 내놓은 뒤) 한 번 호출한다 —
/// [event]가 null이거나(활성 이벤트 없음) 이 기기에서 오늘 이미 봤거나
/// "다시 보지 않기"로 꺼둔 이벤트면 조용히 아무 일도 안 한다. 그 외에는
/// 모달을 띄우고, 뜨는 시점에 바로 "오늘 봤음"을 기록한다(X로 닫든
/// 이미지를 탭해서 이동하든 — 어느 쪽이든 오늘 안에는 다시 안 떠야 하므로
/// 여는 시점에 기록하는 게 두 경로를 따로 처리하는 것보다 단순하다).
Future<void> showHomeEventPopupIfNeeded({
  required BuildContext context,
  required HomeEvent? event,
  required List<StoryPack> allPacks,
}) async {
  if (event == null) return;

  final store = HomeEventDismissalStore();
  if (!await store.shouldShow(event.id)) return;
  if (!context.mounted) return;

  unawaited(store.markShownToday(event.id));

  StoryPack? linkedPack;
  final packId = event.linkedPackId;
  if (packId != null) {
    for (final pack in allPacks) {
      if (pack.id == packId) {
        linkedPack = pack;
        break;
      }
    }
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _HomeEventDialog(
      event: event,
      linkedPack: linkedPack,
      onNeverShowAgain: () => store.markNeverShowAgain(event.id),
    ),
  );
}

class _HomeEventDialog extends StatelessWidget {
  final HomeEvent event;
  final StoryPack? linkedPack;
  final VoidCallback onNeverShowAgain;

  const _HomeEventDialog({
    required this.event,
    required this.linkedPack,
    required this.onNeverShowAgain,
  });

  void _handleTapThrough(BuildContext context) {
    final pack = linkedPack;
    Navigator.pop(context);
    if (pack == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => StoryPackDetailPage(pack: pack)));
  }

  @override
  Widget build(BuildContext context) {
    final title = event.title;
    final hasTitle = title != null && title.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _panelBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _panelBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HomeEventHeader(
                onNeverShowAgain: () {
                  onNeverShowAgain();
                  Navigator.pop(context);
                },
                onClose: () => Navigator.pop(context),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: linkedPack == null ? null : () => _handleTapThrough(context),
                        child: AspectRatio(
                          aspectRatio: 4 / 5,
                          child: event.imageUrl.isNotEmpty
                              ? Image.network(
                                  event.imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const _EventImageFallback(),
                                )
                              : const _EventImageFallback(),
                        ),
                      ),
                      if (hasTitle)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _ivory,
                              height: 1.35,
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 닫기 버튼과 "다시 보지 않기"를 이미지 위가 아니라 별도의 얇은 상단
/// 바에 둔다 — 이미지 위에 얹으면 이벤트 이미지 자체를 가리고 시선을
/// 뺏는다. 둘 다 작고 톤 다운된 스타일(bundle_purchase_flow.dart의
/// _Header와 같은 급)로, "다시 보지 않기"가 X 버튼보다 더 눈에 띄지
/// 않게 왼쪽에 작게 둔다.
class _HomeEventHeader extends StatelessWidget {
  final VoidCallback onNeverShowAgain;
  final VoidCallback onClose;

  const _HomeEventHeader({required this.onNeverShowAgain, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _hairline))),
      child: Row(
        children: [
          Text(
            '이벤트',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: _amber.withOpacity(0.9),
            ),
          ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onNeverShowAgain,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                '다시 보지 않기',
                style: TextStyle(fontSize: 11.5, color: _ivory.withOpacity(0.45)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onClose,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 18, color: _ivory.withOpacity(0.55)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventImageFallback extends StatelessWidget {
  const _EventImageFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF2C2C2A),
      child: Center(
        child: Icon(Icons.image_not_supported_outlined, color: Colors.white.withOpacity(0.3), size: 32),
      ),
    );
  }
}
