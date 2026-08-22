import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio/audio_service.dart';
import '../../core/auth/auth_scope.dart';
import '../../features/story/widgets/typewriter_text.dart';
import 'data/reader_prefs_repository.dart';
import 'models/node_block.dart';
import 'models/node_block_type.dart';
import 'models/node_effects.dart';
import 'models/reader_prefs.dart';
import 'tts_controller.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);
const Color _beatAccent = Color(0xFFFFB648);

/// 데스크톱 리더 레이아웃으로 갈리는 폭 — 카탈로그 쪽 homeDesktopBreakpoint와
/// 같은 값이지만, lib/reader/**가 lib/features/catalog/**를 import하지 않도록
/// 여기 따로 둔다(genres/Genre 사본과 같은 패턴).
const double _desktopBreakpoint = 1100;

/// 데스크톱 설정 사이드바 폭.
const double _settingsPanelWidth = 320;

/// 데스크톱 본문 읽기 폭 — 1440px 화면에서 한 줄이 화면 끝까지 늘어나면
/// 눈이 줄을 놓친다.
const double _desktopReadingWidth = 780;

/// 노드 한 편(= 화면 한 장)을 렌더링하는 공유 프레임. 인터랙티브/선형 리더가
/// 둘 다 이 위로 자기만의 하단 액션 영역(선택지 버튼들 / "다음" 버튼)만 얹는다
/// — 배경, 문단/비트/이미지 블록 타이핑, 설정은 두 리더가 완전히 같은 동작을
/// 공유해야 하므로 여기서 한 번만 구현한다.
///
/// 레이아웃은 폭으로 갈린다:
/// - 좁은 폭: 상단 배경 배너(화면 높이 36%) + 본문 + 하단 접이식 설정 시트.
/// - 데스크톱([_desktopBreakpoint] 이상): 배경이 화면 전체를 채우고, 본문과
///   액션 영역은 하단 스크림 위에 얹힌다. 설정은 하단 시트가 아니라 우상단
///   아이콘 → 오른쪽 사이드바다 — 넓은 화면에서 시트를 그대로 쓰면 컨트롤이
///   화면 폭 전체로 늘어나 읽는 동안 계속 눈에 걸린다.
///
/// 노드가 바뀔 때마다 호출부가 새 [key](예: ValueKey(node.id))로 새
/// SceneFrame 인스턴스를 만드는 것을 전제로 한다 — 그래야 배경 페이드인/타이핑
/// 진행 상태가 자연스럽게 "새 노드 진입"으로 리셋된다.
///
/// Scaffold 자체는 포함하지 않는다 — 호출부(리더 페이지)가 자기 Scaffold의
/// body로 이 위젯을 얹어, 뒤로가기 버튼 등 페이지 단위 크롬은 호출부가 맡는다.
class SceneFrame extends StatefulWidget {
  /// 이 노드의 본문 블록(paragraph/beat/image) — 순서대로 타이핑/표시된다.
  final List<NodeBlock> blocks;

  /// 배경 인계 규칙까지 적용해 이미 resolve된 이미지 URL. null이면 fallback
  /// 그라디언트만 보여준다.
  final String? backgroundImageUrl;

  /// storyPack.ttsEnabled — 이 팩이 TTS 재생을 허용하는지. false면 설정에
  /// TTS 컨트롤 자체가 보이지 않는다.
  final bool ttsAllowed;

  /// 모든 블록이 다 드러난 뒤 보여줄 타입별 액션 영역 — 인터랙티브는 선택지
  /// 버튼들, 선형은 "다음"/"완료" 버튼.
  final WidgetBuilder actionAreaBuilder;

  /// 이 노드의 연출 효과(암전/흔들림/효과음/플래시/진동) — 본문 타이핑이
  /// 끝나는 시점에 전부 동시에 트리거된다.
  final NodeEffects effects;

  /// effects.sfx.sfxId를 sfxLibrary/{sfxId}로 조인해 이미 resolve된 URL.
  /// enabled인데 null/빈 문자열이면 조용히 재생을 건너뛴다.
  final String? sfxUrl;

  const SceneFrame({
    super.key,
    required this.blocks,
    required this.actionAreaBuilder,
    this.backgroundImageUrl,
    this.ttsAllowed = false,
    this.effects = const NodeEffects(),
    this.sfxUrl,
  });

  @override
  State<SceneFrame> createState() => _SceneFrameState();
}

class _SceneFrameState extends State<SceneFrame>
    with SingleTickerProviderStateMixin {
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

  /// 좁은 폭의 하단 시트가 펼쳐졌는지.
  bool _sheetExpanded = false;

  /// 데스크톱 설정 사이드바가 열렸는지 — 기본은 닫힘이다(몰입 방해를 막는 게
  /// 이 레이아웃의 목적).
  bool _settingsOpen = false;

  /// 이 노드 인스턴스에서 연출 효과를 이미 재생했는지 — 타이핑 완료 시점에
  /// 한 번만 트리거한다.
  bool _effectsPlayed = false;

  double _blackoutOpacity = 0;
  Duration _blackoutFadeDuration = const Duration(milliseconds: 250);

  double _flashOpacity = 0;
  Duration _flashFadeDuration = const Duration(milliseconds: 40);
  Color _flashColor = Colors.transparent;

  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  double _shakeAmplitude = 0;

  bool get _typingDone => _blockIndex >= widget.blocks.length;

  @override
  void initState() {
    super.initState();
    _ttsPlayingSub = _tts.playingStream.listen((playing) {
      if (mounted) setState(() => _ttsPlaying = playing);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _bgVisible = true);
      // 블록이 아예 없는 노드는 _advance()/_skipAll() 어느 쪽도 호출될 일이
      // 없어서 _typingDone이 시작부터 true다 — 여기서도 한 번 확인해 둔다.
      _maybePlayEffects();
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
    _shakeController.dispose();
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
    _maybePlayEffects();
  }

  void _skipAll() {
    if (_typingDone) return;
    setState(() => _blockIndex = widget.blocks.length);
    _maybePlayEffects();
  }

  /// 본문이 다 드러난 순간 켜져 있는 연출 효과를 전부 "동시에" 트리거한다 —
  /// 서로 await하지 않는다. [_effectsPlayed]가 유일한 가드다.
  void _maybePlayEffects() {
    if (_effectsPlayed || !_typingDone) return;
    _effectsPlayed = true;

    final effects = widget.effects;
    if (effects.blackout.enabled) {
      _triggerBlackout(effects.blackout.durationPreset.duration);
    }
    if (effects.shake.enabled) {
      _triggerShake(effects.shake.intensityPreset.amplitudePx);
    }
    if (effects.flash.enabled) {
      _triggerFlash(
        effects.flash.colorPreset.color,
        effects.flash.durationPreset.duration,
      );
    }
    if (effects.sfx.enabled) {
      // await하지 않는다 — 재생 완료를 기다리면 haptic 등 뒤 트리거가 밀린다.
      unawaited(_triggerSfx(widget.sfxUrl));
    }
    if (effects.haptic.enabled) {
      _triggerHaptic(effects.haptic.durationPreset);
    }
  }

  void _triggerBlackout(Duration total) {
    final half = Duration(milliseconds: (total.inMilliseconds / 2).round());
    setState(() {
      _blackoutFadeDuration = half;
      _blackoutOpacity = 1;
    });
    Future.delayed(half, () {
      if (!mounted) return;
      setState(() => _blackoutOpacity = 0);
    });
  }

  /// blackout은 반씩 나눠 대칭으로 fade in/out하지만, 플래시는 "번쩍임"으로
  /// 읽혀야 해서 비대칭이다 — 아주 짧게(고정 40ms) 들어왔다가 나머지 구간에
  /// 걸쳐 천천히 빠진다.
  void _triggerFlash(Color color, Duration total) {
    const fadeIn = Duration(milliseconds: 40);
    final fadeOut = total > fadeIn ? total - fadeIn : const Duration(milliseconds: 10);
    setState(() {
      _flashColor = color;
      _flashFadeDuration = fadeIn;
      _flashOpacity = 1;
    });
    Future.delayed(fadeIn, () {
      if (!mounted) return;
      setState(() {
        _flashFadeDuration = fadeOut;
        _flashOpacity = 0;
      });
    });
  }

  void _triggerShake(double amplitudePx) {
    _shakeAmplitude = amplitudePx;
    _shakeController
      ..reset()
      ..forward();
  }

  /// sfxId가 없거나 조인이 실패했거나 URL 로드가 실패해도 디버그 로그만 남기고
  /// 조용히 넘어간다.
  Future<void> _triggerSfx(String? url) async {
    if (url == null || url.isEmpty) {
      debugPrint('노드 효과음 재생 안 함: sfxUrl이 없어요(sfxId 미선택 또는 라이브러리 조인 실패).');
      return;
    }
    await AudioService.instance.playSfx(url);
  }

  void _triggerHaptic(HapticDurationPreset preset) {
    if (preset == HapticDurationPreset.short) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 150), () {
        HapticFeedback.mediumImpact();
      });
    }
  }

  /// 이미지 블록/애니메이션이 꺼진 텍스트 블록처럼 "타이핑 없이 즉시 지나가는"
  /// 블록을 한 프레임 뒤 자동으로 다음 블록으로 넘긴다. index별로 한 번만
  /// 예약한다.
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
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          // 흔들림은 두 레이아웃이 공유한다 — 감쇠하는 사인파로 원위치에
          // 자연스럽게 멎는다.
          AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              final t = _shakeController.value;
              final dx = _shakeAmplitude * math.sin(t * 6 * math.pi) * (1 - t);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: isDesktop ? _buildDesktopScene() : _buildMobileScene(),
          ),
          if (!isDesktop)
            Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomSheet())
          else ...[
            if (!_settingsOpen)
              Positioned(
                right: 20,
                top: 16,
                child: SafeArea(child: _SettingsTriggerButton(onTap: _openSettings)),
              ),
            if (_settingsOpen)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _ReaderSettingsPanel(
                  prefs: _prefs,
                  ttsAllowed: widget.ttsAllowed,
                  ttsPlaying: _ttsPlaying,
                  onClose: _closeSettings,
                  onToggleTts: _toggleTtsPlayback,
                  onToggleBgm: _toggleBgm,
                  onFontSelected: (fontId) => _updatePrefs(_prefs.copyWith(fontId: fontId)),
                  onAnimationToggled: (enabled) =>
                      _updatePrefs(_prefs.copyWith(animationEnabled: enabled)),
                ),
              ),
          ],
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _blackoutOpacity,
                duration: _blackoutFadeDuration,
                curve: Curves.easeInOut,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
          // 블랙아웃과 같은 오버레이 메커니즘을 재사용한 독립 레이어 — 색/
          // 지속시간 상태를 따로 들고 있어서 동시에 켜져도 서로 안 덮어쓴다.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _flashOpacity,
                duration: _flashFadeDuration,
                curve: Curves.easeOut,
                child: ColoredBox(color: _flashColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSettings() => setState(() => _settingsOpen = true);
  void _closeSettings() => setState(() => _settingsOpen = false);

  /// 좁은 폭 — 상단 배경 배너 + 본문 + 액션 영역(기존 그대로).
  Widget _buildMobileScene() {
    return Column(
      children: [
        _BackgroundBanner(url: widget.backgroundImageUrl, visible: _bgVisible),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 28, child: _buildSkipButton()),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildVisibleBlocks(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildActionArea(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 데스크톱 — 배경이 화면 전체를 채우고, 본문/액션은 하단 스크림 위에 얹힌다.
  ///
  /// 설정 사이드바가 열리면 본문과 액션 영역을 패널 폭만큼 안으로 밀어 넣는다
  /// — 안 그러면 오른쪽 선택지가 패널 아래로 들어가 눌리지 않는다.
  Widget _buildDesktopScene() {
    final url = widget.backgroundImageUrl;
    final rightInset = _settingsOpen ? _settingsPanelWidth + 60 : 60.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: _bgVisible ? 1 : 0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          child: url != null && url.isNotEmpty
              ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _BannerFallback(),
                )
              : const _BannerFallback(),
        ),
        // 본문이 사진 위에서도 읽히도록 아래로 갈수록 짙어지는 스크림.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xF0000000), Color(0x8C000000), Colors.transparent],
              stops: [0.0, 0.34, 0.62],
            ),
          ),
        ),
        Positioned(
          left: 60,
          right: 0,
          bottom: 40,
          child: Padding(
            padding: EdgeInsets.only(right: rightInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _desktopReadingWidth,
                  child: Align(alignment: Alignment.centerRight, child: _buildSkipButton()),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _desktopReadingWidth,
                    maxHeight: 320,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildVisibleBlocks(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _buildActionArea(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildSkipButton() {
    if (_typingDone) return null;
    return TextButton(
      onPressed: _skipAll,
      style: TextButton.styleFrom(foregroundColor: _ivory.withOpacity(0.75)),
      child: const Text(
        '전체 보기',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildActionArea() {
    return AnimatedOpacity(
      opacity: _typingDone ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !_typingDone,
        child: widget.actionAreaBuilder(context),
      ),
    );
  }

  List<Widget> _buildVisibleBlocks() {
    return [
      for (var i = 0; i < widget.blocks.length && i <= _blockIndex; i++)
        _buildBlock(widget.blocks[i], index: i),
    ];
  }

  Widget _buildBlock(NodeBlock block, {required int index}) {
    final completed = index < _blockIndex;

    switch (block.type) {
      case NodeBlockType.image:
        if (!completed) {
          _scheduleAutoAdvance(index, delay: const Duration(milliseconds: 550));
        }
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
  /// 아직 번들하지 않은 폰트라 플랫폼 기본 대체 글꼴로 떨어진다.
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
      onAnimationToggled: (enabled) =>
          _updatePrefs(_prefs.copyWith(animationEnabled: enabled)),
    );
  }
}

/// 데스크톱 우상단의 설정 진입 버튼 — 읽는 동안 화면에 남는 유일한 크롬이다.
/// 사이드바가 열려 있는 동안에는 아예 렌더하지 않는다(패널이 이 자리를 덮어
/// 버튼이 닫기 X 아래에 깔린다).
class _SettingsTriggerButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SettingsTriggerButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.42),
        ),
        child: Icon(Icons.tune_rounded, color: _ivory.withOpacity(0.85), size: 21),
      ),
    );
  }
}

/// 데스크톱 설정 사이드바 — 하단 시트와 같은 컨트롤(TTS / BGM / 글꼴 /
/// 글자 애니메이션)을 같은 위젯([_SheetIconToggle], [_FontChip])으로 그린다.
/// 두 레이아웃이 각자 컨트롤을 들고 있다가 어긋나는 걸 막는다.
class _ReaderSettingsPanel extends StatelessWidget {
  final ReaderPrefs prefs;
  final bool ttsAllowed;
  final bool ttsPlaying;
  final VoidCallback onClose;
  final VoidCallback onToggleTts;
  final VoidCallback onToggleBgm;
  final ValueChanged<String> onFontSelected;
  final ValueChanged<bool> onAnimationToggled;

  const _ReaderSettingsPanel({
    required this.prefs,
    required this.ttsAllowed,
    required this.ttsPlaying,
    required this.onClose,
    required this.onToggleTts,
    required this.onToggleBgm,
    required this.onFontSelected,
    required this.onAnimationToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _settingsPanelWidth,
      decoration: BoxDecoration(
        color: const Color(0xF5080807),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.10))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '설정',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ivory),
                  ),
                  const Spacer(),
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onClose,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, size: 20, color: _ivory.withOpacity(0.55)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  if (ttsAllowed) ...[
                    _SheetIconToggle(
                      icon: ttsPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                      label: 'TTS',
                      active: ttsPlaying,
                      onTap: onToggleTts,
                    ),
                    const SizedBox(width: 14),
                  ],
                  _SheetIconToggle(
                    icon: prefs.bgmEnabled ? Icons.music_note_rounded : Icons.music_off_rounded,
                    label: 'BGM',
                    active: prefs.bgmEnabled,
                    onTap: onToggleBgm,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(height: 1, thickness: 1, color: Colors.white.withOpacity(0.08)),
              const SizedBox(height: 20),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    '글자 애니메이션',
                    style: TextStyle(color: _ivory, fontSize: 12.5),
                  ),
                  const Spacer(),
                  Switch(
                    value: prefs.animationEnabled,
                    activeThumbColor: _gold,
                    onChanged: onAnimationToggled,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  )
                : const SizedBox.shrink(),
          ),
          if (block.caption != null && block.caption!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              block.caption!,
              style: TextStyle(
                fontSize: 12.5,
                color: _ivory.withOpacity(0.6),
                fontStyle: FontStyle.italic,
              ),
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
                            icon: ttsPlaying
                                ? Icons.pause_circle_rounded
                                : Icons.play_circle_rounded,
                            label: 'TTS',
                            active: ttsPlaying,
                            onTap: onToggleTts,
                          ),
                        if (ttsAllowed) const SizedBox(width: 14),
                        _SheetIconToggle(
                          icon: prefs.bgmEnabled
                              ? Icons.music_note_rounded
                              : Icons.music_off_rounded,
                          label: 'BGM',
                          active: prefs.bgmEnabled,
                          onTap: onToggleBgm,
                        ),
                        const Spacer(),
                        const Text(
                          '글자 애니메이션',
                          style: TextStyle(color: _ivory, fontSize: 12.5),
                        ),
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
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _SheetIconToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SheetIconToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

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
            Text(
              label,
              style: TextStyle(
                color: active ? _gold : _ivory.withOpacity(0.5),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
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
          border: Border.all(
            color: selected ? _gold.withOpacity(0.6) : Colors.white.withOpacity(0.12),
          ),
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
