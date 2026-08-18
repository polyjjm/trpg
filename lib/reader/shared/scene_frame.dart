import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_service.dart';
import '../../core/auth/auth_scope.dart';
import '../../features/story/widgets/typewriter_text.dart';
import 'data/reader_prefs_repository.dart';
import 'models/node_block.dart';
import 'models/node_block_type.dart';
import 'models/reader_prefs.dart';
import 'tts_controller.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);
const Color _beatAccent = Color(0xFFFFB648);

/// 노드 한 편(= 화면 한 장)을 렌더링하는 공유 프레임. 인터랙티브/선형 리더가
/// 둘 다 이 위로 자기만의 하단 액션 영역(선택지 버튼들 / "다음" 버튼)만 얹는다
/// — 배경 배너, 문단/비트/이미지 블록 타이핑, 설정 시트는 두 리더가 완전히
/// 같은 동작을 공유해야 하므로 여기서 한 번만 구현한다.
///
/// 노드가 바뀔 때마다 호출부가 새 [key](예: ValueKey(node.id))로 새
/// SceneFrame 인스턴스를 만드는 것을 전제로 한다 — 그래야 배경 페이드인/타이핑
/// 진행 상태가 자연스럽게 "새 노드 진입"으로 리셋된다. 같은 인스턴스를 두고
/// props만 갱신하는 방식은 지원하지 않는다(didUpdateWidget에서 진행 상태를
/// 다시 계산하지 않는다).
///
/// Scaffold 자체는 포함하지 않는다 — 호출부(리더 페이지)가 자기 Scaffold의
/// body로 이 위젯을 얹어, 뒤로가기 버튼 등 페이지 단위 크롬은 호출부가 맡는다.
class SceneFrame extends StatefulWidget {
  /// 이 노드의 본문 블록(paragraph/beat/image) — 순서대로 타이핑/표시된다.
  final List<NodeBlock> blocks;

  /// 배경 인계 규칙(lib/core/story/background_image_inheritance.dart)까지
  /// 적용해 이미 resolve된 이미지 URL. null이면 배너는 fallback 그라디언트만
  /// 보여준다.
  final String? backgroundImageUrl;

  /// storyPack.ttsEnabled — 이 팩이 TTS 재생을 허용하는지. false면 설정
  /// 시트에 TTS 컨트롤 자체가 보이지 않는다(readerPrefs.ttsEnabled과는 별개
  /// 축 — 팩 단위 허용 여부 vs 사용자 개인 설정).
  final bool ttsAllowed;

  /// 모든 블록이 다 드러난 뒤(또는 "전체 보기"로 건너뛴 뒤) 보여줄 타입별
  /// 액션 영역 — 인터랙티브는 선택지 버튼들, 선형은 "다음"/"완료" 버튼.
  final WidgetBuilder actionAreaBuilder;

  const SceneFrame({
    super.key,
    required this.blocks,
    required this.actionAreaBuilder,
    this.backgroundImageUrl,
    this.ttsAllowed = false,
  });

  @override
  State<SceneFrame> createState() => _SceneFrameState();
}

class _SceneFrameState extends State<SceneFrame> {
  final ReaderPrefsRepository _prefsRepository = ReaderPrefsRepository();
  final TtsController _tts = TtsController();

  StreamSubscription<ReaderPrefs>? _prefsSub;
  StreamSubscription<bool>? _ttsPlayingSub;
  String? _uid;
  bool _resolvedUid = false;

  ReaderPrefs _prefs = ReaderPrefs.defaults;
  bool _ttsPlaying = false;

  int _blockIndex = 0;
  int? _autoAdvancedIndex;
  bool _bgVisible = false;
  bool _sheetExpanded = false;

  bool get _typingDone => _blockIndex >= widget.blocks.length;

  @override
  void initState() {
    super.initState();
    _ttsPlayingSub = _tts.playingStream.listen((playing) {
      if (mounted) setState(() => _ttsPlaying = playing);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _bgVisible = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_resolvedUid) {
      _resolvedUid = true;
      _uid = AuthScope.of(context).userId;
      final uid = _uid;
      if (uid != null) {
        _prefsSub = _prefsRepository.watch(uid).listen((prefs) {
          if (mounted) setState(() => _prefs = prefs);
        });
      }
    }
  }

  @override
  void dispose() {
    _prefsSub?.cancel();
    _ttsPlayingSub?.cancel();
    _tts.dispose();
    super.dispose();
  }

  void _updatePrefs(ReaderPrefs next) {
    setState(() => _prefs = next);
    final uid = _uid;
    if (uid != null) _prefsRepository.save(uid, next);
  }

  void _advance() {
    if (_blockIndex >= widget.blocks.length) return;
    setState(() => _blockIndex += 1);
  }

  void _skipAll() {
    if (_typingDone) return;
    setState(() => _blockIndex = widget.blocks.length);
  }

  /// 이미지 블록/애니메이션이 꺼진 텍스트 블록처럼 "타이핑 없이 즉시 지나가는"
  /// 블록을 한 프레임 뒤 자동으로 다음 블록으로 넘긴다. index별로 한 번만
  /// 예약한다 — build()가 여러 번 불려도 중복 예약되지 않도록.
  void _scheduleAutoAdvance(int index, {Duration delay = Duration.zero}) {
    if (_autoAdvancedIndex == index) return;
    _autoAdvancedIndex = index;
    Future.delayed(delay, () {
      if (mounted) _advance();
    });
  }

  String get _combinedTtsText {
    return widget.blocks
        .map((b) => b.type == NodeBlockType.image ? (b.caption ?? '') : (b.ttsText ?? ''))
        .where((s) => s.trim().isNotEmpty)
        .join('. ');
  }

  void _toggleTtsPlayback() {
    if (_ttsPlaying) {
      _tts.pause();
      _updatePrefs(_prefs.copyWith(ttsEnabled: false));
    } else {
      _tts.play(_combinedTtsText);
      _updatePrefs(_prefs.copyWith(ttsEnabled: true));
    }
  }

  void _toggleBgm() {
    final next = !_prefs.bgmEnabled;
    AudioService.instance.setBgmMuted(!next);
    _updatePrefs(_prefs.copyWith(bgmEnabled: next));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          Column(
            children: [
              _BackgroundBanner(url: widget.backgroundImageUrl, visible: _bgVisible),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 28,
                        child: !_typingDone
                            ? Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _skipAll,
                                  style: TextButton.styleFrom(foregroundColor: _ivory.withOpacity(0.75)),
                                  child: const Text('전체 보기', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                ),
                              )
                            : null,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < widget.blocks.length && i <= _blockIndex; i++)
                                _buildBlock(widget.blocks[i], index: i),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      AnimatedOpacity(
                        opacity: _typingDone ? 1 : 0,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOut,
                        child: IgnorePointer(
                          ignoring: !_typingDone,
                          child: widget.actionAreaBuilder(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomSheet()),
        ],
      ),
    );
  }

  Widget _buildBlock(NodeBlock block, {required int index}) {
    final completed = index < _blockIndex;

    switch (block.type) {
      case NodeBlockType.image:
        if (!completed) _scheduleAutoAdvance(index, delay: const Duration(milliseconds: 550));
        return _ImageBlockView(block: block);
      case NodeBlockType.paragraph:
      case NodeBlockType.beat:
        final isBeat = block.type == NodeBlockType.beat;
        final style = _textStyleFor(isBeat: isBeat, fontId: _prefs.fontId);
        final text = block.text ?? '';

        if (completed || !_prefs.animationEnabled) {
          if (!completed) _scheduleAutoAdvance(index);
          return Padding(
            padding: EdgeInsets.only(bottom: isBeat ? 22 : 16),
            child: Text(text, style: style),
          );
        }

        return Padding(
          padding: EdgeInsets.only(bottom: isBeat ? 22 : 16),
          child: TypewriterText(
            text: text,
            style: style,
            speed: Duration(milliseconds: _prefs.typingSpeedMs),
            onComplete: _advance,
          ),
        );
    }
  }

  TextStyle _textStyleFor({required bool isBeat, required String fontId}) {
    final fontFamily = _fontFamilyFor(fontId);
    if (isBeat) {
      return TextStyle(
        fontSize: 15,
        height: 2.0,
        color: _beatAccent,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        fontFamily: fontFamily,
        fontFamilyFallback: const ['NotoSansKR'],
      );
    }
    return TextStyle(
      fontSize: 16,
      height: 1.75,
      color: Colors.white,
      fontFamily: fontFamily,
      fontFamilyFallback: const ['NotoSansKR'],
    );
  }

  /// null을 반환하면 테마 기본값(NotoSansKR)을 그대로 쓴다. 'serif'/'mono'는
  /// 아직 이 프로젝트가 번들하지 않은 폰트라 플랫폼 기본 대체 글꼴로
  /// 떨어진다 — 실제 서체 애셋이 추가되기 전까지의 자리 표시자다.
  String? _fontFamilyFor(String fontId) {
    switch (fontId) {
      case 'serif':
        return 'Georgia';
      case 'mono':
        return 'Courier';
      default:
        return null;
    }
  }

  Widget _buildBottomSheet() {
    return _ReaderSettingsSheet(
      expanded: _sheetExpanded,
      onToggleExpanded: () => setState(() => _sheetExpanded = !_sheetExpanded),
      prefs: _prefs,
      ttsAllowed: widget.ttsAllowed,
      ttsPlaying: _ttsPlaying,
      onToggleTts: _toggleTtsPlayback,
      onToggleBgm: _toggleBgm,
      onFontSelected: (fontId) => _updatePrefs(_prefs.copyWith(fontId: fontId)),
      onAnimationToggled: (enabled) => _updatePrefs(_prefs.copyWith(animationEnabled: enabled)),
    );
  }
}

class _BackgroundBanner extends StatelessWidget {
  final String? url;
  final bool visible;

  const _BackgroundBanner({required this.url, required this.visible});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.36;
    final url = this.url;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && url.isNotEmpty)
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _BannerFallback(),
              )
            else
              const _BannerFallback(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black],
                  stops: [0.45, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF241F1A), Colors.black],
        ),
      ),
    );
  }
}

class _ImageBlockView extends StatelessWidget {
  final NodeBlock block;

  const _ImageBlockView({required this.block});

  @override
  Widget build(BuildContext context) {
    final url = block.url;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: url != null && url.isNotEmpty
                ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
                : const SizedBox.shrink(),
          ),
          if (block.caption != null && block.caption!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              block.caption!,
              style: TextStyle(fontSize: 12.5, color: _ivory.withOpacity(0.6), fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}

const List<({String id, String label})> _fontOptions = [
  (id: 'default', label: '기본'),
  (id: 'serif', label: '세리프'),
  (id: 'mono', label: '모노'),
];

class _ReaderSettingsSheet extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ReaderPrefs prefs;
  final bool ttsAllowed;
  final bool ttsPlaying;
  final VoidCallback onToggleTts;
  final VoidCallback onToggleBgm;
  final ValueChanged<String> onFontSelected;
  final ValueChanged<bool> onAnimationToggled;

  const _ReaderSettingsSheet({
    required this.expanded,
    required this.onToggleExpanded,
    required this.prefs,
    required this.ttsAllowed,
    required this.ttsPlaying,
    required this.onToggleTts,
    required this.onToggleBgm,
    required this.onFontSelected,
    required this.onAnimationToggled,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggleExpanded,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -80 && !expanded) onToggleExpanded();
        if (velocity > 80 && expanded) onToggleExpanded();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        height: expanded ? 210 : 26,
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xF0151515),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: expanded
            ? Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHandle(),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (ttsAllowed)
                          _SheetIconToggle(
                            icon: ttsPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                            label: 'TTS',
                            active: ttsPlaying,
                            onTap: onToggleTts,
                          ),
                        if (ttsAllowed) const SizedBox(width: 14),
                        _SheetIconToggle(
                          icon: prefs.bgmEnabled ? Icons.music_note_rounded : Icons.music_off_rounded,
                          label: 'BGM',
                          active: prefs.bgmEnabled,
                          onTap: onToggleBgm,
                        ),
                        const Spacer(),
                        const Text('글자 애니메이션', style: TextStyle(color: _ivory, fontSize: 12.5)),
                        Switch(
                          value: prefs.animationEnabled,
                          activeThumbColor: _gold,
                          onChanged: onAnimationToggled,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final option in _fontOptions) ...[
                          _FontChip(
                            label: option.label,
                            selected: prefs.fontId == option.id,
                            onTap: () => onFontSelected(option.id),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ],
                ),
              )
            : Center(child: _buildHandle()),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
    );
  }
}

class _SheetIconToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SheetIconToggle({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: active ? _gold : _ivory.withOpacity(0.5), size: 26),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: active ? _gold : _ivory.withOpacity(0.5), fontSize: 12.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _FontChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FontChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _gold.withOpacity(0.18) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? _gold.withOpacity(0.6) : Colors.white.withOpacity(0.12)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _gold : _ivory.withOpacity(0.65),
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
