import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/audio/audio_service.dart';
import '../../core/auth/auth_scope.dart';
import '../../features/story/widgets/typewriter_text.dart';
import 'data/reader_prefs_repository.dart';
import 'models/node_block.dart';
import 'models/node_block_type.dart';
import 'models/node_effects.dart';
import 'models/reader_prefs.dart';
import 'node_tts_playback_controller.dart';

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

/// 배경 이미지가 없는 노드의 "책 읽기 모드" 지면 폭(한 쪽 / 두 쪽).
const double _bookPageWidth = 720;
const double _bookSpreadWidth = 1000;

/// 책 모드 본문 줄간감 — 사진 위에 얹힐 때(1.75)보다 넣는 리듬으로 읽힌다.
const double _bookLineHeight = 2.05;

/// 지면 배경/경계선 — 오른족이 안된 종이 톤.
const Color _bookPaperTop = Color(0xFF15120F);
const Color _bookPaperBottom = Color(0xFF100E0C);

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
  /// synthesizeNodeTts 호출에 쓰는 팩 id — TTS 오디오는 서버(Cloud Function)가
  /// liveSnapshot에서 직접 본문/연출 설정을 읽어 만들기 때문에, 클라이언트는
  /// 텍스트 자체가 아니라 id만 넘기면 된다.
  final String packId;

  /// 이 화면에서 순서대로 이어 읽을 노드 id 목록 — 보통 원소 하나짜리
  /// 목록(노드 하나짜리 화면)이지만, 선형 리더의 두 쪽 펼침 모드는 왼쪽/
  /// 오른쪽 쪽이 서로 다른 노드라 두 개짜리 목록이 된다. TTS 재생 버튼은
  /// 이 순서대로 이어 튼다(NodeTtsPlaybackController.playSequence) — 화면
  /// 전환 없이 왼쪽 쪽 내레이션이 끝나면 곧바로 오른쪽 쪽으로 넘어간다.
  final List<String> narrationNodeIds;

  /// 이 목록의 내레이션이 (일시정지가 아니라) 끝까지 자연 재생됐을 때 한
  /// 번 불린다 — 호출부(리더 페이지)가 자동 이어재생 여부를 판단해 다음
  /// 노드/스프레드로 넘어갈지 정한다(요청 사양 Part 2).
  final VoidCallback? onNarrationCompleted;

  /// ReaderPrefs.ttsAutoContinueEnabled가 로드되거나 바뀔 때마다 알려준다 —
  /// 자동 이어재생 여부 판단은 SceneFrame이 아니라 리더 페이지의
  /// ReaderSessionController가 하므로(클래스 doc "narrationNodeIds" 참고),
  /// 그 값을 여기서 밖으로 흘려보낸다.
  final ValueChanged<bool>? onAutoContinuePrefsChanged;

  /// 사용자가 이 화면의 TTS 버튼을 직접 눌러 켜거나(true) 껐을(false) 때
  /// 알려준다 — 내레이션이 자연 종료돼서 [_ttsPlaying]이 false가 되는
  /// 경우는 포함하지 않는다(그건 사용자가 끈 게 아니다). 호출부(리더
  /// 페이지)가 이 값을 ReaderSessionController에 그대로 저장해 뒀다가,
  /// 다음 노드의 [autoPlayNarration]을 결정하는 데 쓴다.
  final ValueChanged<bool>? onNarrationUserToggled;

  /// true면 이 화면에 들어오자마자(사용자가 TTS 버튼을 다시 누르지 않아도)
  /// 내레이션을 자동으로 재생한다 — 호출부가 "사용자가 TTS를 켜 둔 상태"를
  /// 그대로 넘겨준다(자동 이어재생으로 들어왔든, 선택지를 직접 탭해서
  /// 들어왔든, "다음" 버튼을 눌러서 들어왔든 경로와 무관하다 — 리더가
  /// 스스로 TTS를 한 번 켠 뒤로는 노드가 어떻게 바뀌든 계속 듣고 싶어한다는
  /// 뜻이라서다). 아직 한 번도 TTS를 켜지 않은 세션(최초 진입 등)은 항상
  /// false — 리더가 직접 TTS 버튼을 눌러야 시작된다.
  final bool autoPlayNarration;

  /// 이 노드의 본문 블록(paragraph/beat/image) — 순서대로 타이핑/표시된다.
  final List<NodeBlock> blocks;

  /// 배경 인계 규칙까지 적용해 이미 resolve된 이미지 URL. null이면 fallback
  /// 그라디언트만 보여준다.
  final String? backgroundImageUrl;

  /// 모든 블록이 다 드러난 뒤 보여줄 타입별 액션 영역 — 인터랙티브는 선택지
  /// 버튼들, 선형은 "다음"/"완료" 버튼.
  final WidgetBuilder actionAreaBuilder;

  /// 이 노드의 연출 효과(암전/흔들림/효과음/플래시/진동) — 본문 타이핑이
  /// 끝나는 시점에 전부 동시에 트리거된다.
  final NodeEffects effects;

  /// effects.sfx.sfxId를 sfxLibrary/{sfxId}로 조인해 이미 resolve된 URL.
  /// enabled인데 null/빈 문자열이면 조용히 재생을 건너뛴다.
  final String? sfxUrl;

  /// 책 읽기 모드 지면 상단에 찍는 라벨·제목·쪽번호(전부 선택) —
  /// 배경 이미지가 있는 노드(시네마핅)에선 쓰지 않는다. LinearReader가
  /// 노드 순서로 "12화" / "12 / 34"를 만들어 넘긴다.
  final String? chapterLabel;
  final String? chapterTitle;
  final String? progressLabel;

  /// 두 쪽 펼침을 "노드 단위"로 갈러 그릴 때 — 호출부가 다음 노드의
  /// 바록을 [blocks] 뒤에 이어 붙여 넘기고, 이 인덱스부터가 오른쪽 쪽이라고
  /// 알려준다. null이다면 바록 개수 절반으로 나눈다(한 노드를 두 쪽에
  /// 나눠 단는 기존 동작).
  final int? spreadSplitIndex;

  /// 오른쪽 쪽이 다른 노드일 때 그 노드의 쪽 표기.
  final String? secondaryChapterLabel;
  final String? secondaryProgressLabel;

  /// 설정에서 "쪽 보기"가 바뀔 때 알려준다 — 두 페이지를 노드 단위로 펼치는
  /// 판단은 호출부(LinearReader)가 하므로 그쪽도 변경을 알아야 한다. 게스트는
  /// readerPrefs 문서가 없어 Firestore를 통해 전달되지 않는다.
  final ValueChanged<String>? onPageModeChanged;

  /// true면 설정에서 TTS·BGM·글자 애니메이션을 감춘다(선형 리더) — 선형은
  /// 책 모드에서 타이핑을 쓰지 않아 애니메이션 토글이 아무것도 하지 않는다.
  /// 글꼴·글자 크기·글자 색은 두 리더 모두 보여준다.
  final bool simplifiedSettings;

  const SceneFrame({
    super.key,
    required this.packId,
    required this.narrationNodeIds,
    this.onNarrationCompleted,
    this.onAutoContinuePrefsChanged,
    this.onNarrationUserToggled,
    this.autoPlayNarration = false,
    required this.blocks,
    required this.actionAreaBuilder,
    this.backgroundImageUrl,
    this.effects = const NodeEffects(),
    this.sfxUrl,
    this.chapterLabel,
    this.chapterTitle,
    this.progressLabel,
    this.spreadSplitIndex,
    this.secondaryChapterLabel,
    this.secondaryProgressLabel,
    this.onPageModeChanged,
    this.simplifiedSettings = false,
  });

  @override
  State<SceneFrame> createState() => _SceneFrameState();
}

class _SceneFrameState extends State<SceneFrame>
    with SingleTickerProviderStateMixin {
  final ReaderPrefsRepository _prefsRepository = ReaderPrefsRepository();
  final NodeTtsPlaybackController _tts = NodeTtsPlaybackController();

  StreamSubscription<ReaderPrefs>? _prefsSub;
  StreamSubscription<bool>? _ttsPlayingSub;
  StreamSubscription<bool>? _ttsLoadingSub;
  StreamSubscription<void>? _ttsAllCompletedSub;
  String? _uid;
  bool _resolvedUid = false;

  ReaderPrefs _prefs = ReaderPrefs.defaults;

  /// 이 화면에서 설정을 한 번이라도 직접 바꿨는지 — 그 뒤로는 readerPrefs
  /// 스냅샷으로 값을 덮지 않는다. 저장이 실패하는 환경(보안 규칙이 새 필드를
  /// 막는 등)에서 스냅샷이 예전 값을 다시 흘려보내면, 방금 고른 글꼴·크기가
  /// 조용히 되돌아가 "설정이 안 먹는다"처럼 보였다.
  bool _prefsTouchedLocally = false;
  bool _ttsPlaying = false;
  bool _ttsLoading = false;

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
    _ttsLoadingSub = _tts.loadingStream.listen((loading) {
      if (mounted) setState(() => _ttsLoading = loading);
    });
    _ttsAllCompletedSub = _tts.allCompletedStream.listen((_) {
      widget.onNarrationCompleted?.call();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _bgVisible = true);
      // 블록이 아예 없는 노드는 _advance()/_skipAll() 어느 쪽도 호출될 일이
      // 없어서 _typingDone이 시작부터 true다 — 여기서도 한 번 확인해 둔다.
      _maybePlayEffects();
    });
    if (widget.autoPlayNarration) {
      // 사용자가 TTS를 켜 둔 채로 들어온 노드 — 손대지 않아도 바로 이어
      // 낭독을 시작한다. 텍스트 타이핑 애니메이션과는 무관하게 독립적으로
      // 재생한다(둘의 동기화는 나중 개선 과제 — TTS 기능 자체의 기존 설계
      // 그대로). 이 노드에 TTS가 아예 없으면(요청 사양: "If a node has no
      // TTS configured/cached, auto-advance simply doesn't trigger... —
      // silent, no error") synthesize가 실패하는데, 수동 탭(_toggleTtsPlayback)
      // 과 달리 여기는 스낵바를 띄우지 않는다 — 매번 자동으로 시도하는
      // 자리에서 실패할 때마다 알림을 띄우면 오히려 방해가 된다.
      unawaited(
        _tts
            .playSequence(
              packId: widget.packId,
              nodeIds: widget.narrationNodeIds,
            )
            .catchError((Object _) {}),
      );
    }
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
          if (!mounted || _prefsTouchedLocally) return;
          setState(() => _prefs = prefs);
          AudioService.instance.setBgmMasterVolume(prefs.bgmMasterVolume);
          widget.onAutoContinuePrefsChanged?.call(prefs.ttsAutoContinueEnabled);
        });
      }
    }
  }

  @override
  void dispose() {
    _prefsSub?.cancel();
    _ttsPlayingSub?.cancel();
    _ttsLoadingSub?.cancel();
    _ttsAllCompletedSub?.cancel();
    _tts.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _updatePrefs(ReaderPrefs next) {
    _prefsTouchedLocally = true;
    setState(() => _prefs = next);
    widget.onAutoContinuePrefsChanged?.call(next.ttsAutoContinueEnabled);
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
    final fadeOut = total > fadeIn
        ? total - fadeIn
        : const Duration(milliseconds: 10);
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

  /// 본문 텍스트를 직접 읽어주던 기기 TTS와 달리, 실제 오디오는
  /// synthesizeNodeTts(Cloud Function)가 liveSnapshot에서 직접 만든다 — 여기선
  /// packId/narrationNodeIds만 넘긴다(클래스 doc 참고). 생성 중엔
  /// [_ttsLoading]이 true라 중복 탭이 걸러진다
  /// (NodeTtsPlaybackController.playSequence 참고).
  Future<void> _toggleTtsPlayback() async {
    if (_ttsLoading) return;
    if (_ttsPlaying) {
      await _tts.pause();
      widget.onNarrationUserToggled?.call(false);
      return;
    }
    try {
      await _tts.playSequence(
        packId: widget.packId,
        nodeIds: widget.narrationNodeIds,
      );
      widget.onNarrationUserToggled?.call(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('내레이션을 불러오지 못했어요: $e')));
    }
  }

  /// BGM 볼륨 슬라이더가 드래그하는 동안 매번 부른다 — [_updatePrefs]와 달리
  /// Firestore에는 아직 안 쓴다(드래그 중 매 프레임 쓰기는 낭비다). 대신
  /// AudioService에는 즉시 반영해서 드래그하는 동안 소리가 실시간으로
  /// 바뀌게 한다. 손을 떼면([_commitBgmVolume]) 그제서야 저장한다.
  void _handleBgmVolumeChanged(double volume) {
    _prefsTouchedLocally = true;
    setState(() => _prefs = _prefs.copyWith(bgmMasterVolume: volume));
    AudioService.instance.setBgmMasterVolume(volume);
  }

  /// 슬라이더에서 손을 뗀 시점(Slider.onChangeEnd) — 그 시점의 값을 저장한다.
  /// 음소거 아이콘 버튼(0%/100% 토글)도 드래그가 아니라 즉시 확정이라
  /// [_handleBgmVolumeChanged] 다음에 곧바로 이걸 부른다. 인자로 받는 값은
  /// 안 쓴다 — [_handleBgmVolumeChanged]가 이미 [_prefs]에 반영해 뒀으므로
  /// 그 상태를 그대로 저장하면 된다(Slider.onChangeEnd/[_BgmVolumeRow]의
  /// 콜백 타입을 맞추려고만 받는다).
  void _commitBgmVolume(double _) {
    final uid = _uid;
    if (uid != null) _prefsRepository.save(uid, _prefs);
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
                child: SafeArea(
                  child: _SettingsTriggerButton(onTap: _openSettings),
                ),
              ),
            if (_settingsOpen)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _ReaderSettingsPanel(
                  prefs: _prefs,
                  simplified: widget.simplifiedSettings,
                  onFontScaleSelected: (scale) =>
                      _updatePrefs(_prefs.copyWith(fontScale: scale)),
                  onTextColorSelected: (id) =>
                      _updatePrefs(_prefs.copyWith(textColorId: id)),
                  ttsPlaying: _ttsPlaying,
                  ttsLoading: _ttsLoading,
                  onClose: _closeSettings,
                  onToggleTts: _toggleTtsPlayback,
                  onBgmVolumeChanged: _handleBgmVolumeChanged,
                  onBgmVolumeCommitted: _commitBgmVolume,
                  onFontSelected: (fontId) =>
                      _updatePrefs(_prefs.copyWith(fontId: fontId)),
                  onPageModeSelected: (mode) {
                    _updatePrefs(_prefs.copyWith(pageMode: mode));
                    widget.onPageModeChanged?.call(mode);
                  },
                  onAnimationToggled: (enabled) =>
                      _updatePrefs(_prefs.copyWith(animationEnabled: enabled)),
                  onAutoContinueToggled: (enabled) => _updatePrefs(
                    _prefs.copyWith(ttsAutoContinueEnabled: enabled),
                  ),
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

  /// 배경 이미지가 없는 노드 — 가운데 지면에 얹어 책처럼 읽힌다.
  ///
  /// 한 쪽([ReaderPrefs.pageModeSingle])이면 720px 지면 하나, 두 쪽
  /// ([ReaderPrefs.pageModeSpread])이면 1000px 안에 두 쪽을 펼치고 가운데
  /// 접힘선을 둔다. 두 쪽 나누기는 블록 단위다 — 문단/비트를 앞쪽 절반과
  /// 뒤쪽 절반으로 갈라 담는다. 글자 높이를 재서 정확히 넘치는 지점을 찾는
  /// 방식이 아니라(그건 렌더 후 측정이 필요하다) 블록 개수 기준이라,
  /// 문단 하나가 한 쪽보다 길면 그 쪽만 스크롤된다.
  Widget _buildBookScene() {
    final blocks = _buildVisibleBlocks();
    // 두 쪽은 나눌 분량이 있을 때만 펼친다 — 바로 밑에서 반으로 갈라
    // 담기 때문에, 문단이 하나밖이면 오른쪽 쪽이 통째로 뱈다.
    // ⚠️ spreadSplitIndex가 있으면 호출부가 이미 "두 페이지를 펼쳐 달라"고
    // 정한 것이다 — 이때 자기 _prefs를 다시 보면 안 된다. 펼침으로 바뀌는
    // 순간 리더가 넘기는 key가 달라져서(id1+id2) 이 State가 새로 만들어지고,
    // _prefs는 문서 스냅샷이 다시 오기 전까지 기본값(한 쪽)이라 두 페이지를
    // 받아 놓고도 한 쪽으로 그리게 된다(게스트는 스냅샷이 아예 안 온다).
    final spread =
        (widget.spreadSplitIndex != null || _prefs.isSpread) &&
        blocks.length >= 2;
    final rightInset = _settingsOpen ? _settingsPanelWidth : 0.0;

    return Padding(
      padding: EdgeInsets.only(right: rightInset),
      child: Center(
        child: SizedBox(
          width: spread ? _bookSpreadWidth : _bookPageWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 64, 0, 40),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_bookPaperTop, _bookPaperBottom],
                ),
                border: Border.symmetric(
                  vertical: BorderSide(color: _ivory.withOpacity(0.10)),
                ),
              ),
              child: spread ? _buildSpread(blocks) : _buildSinglePage(blocks),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSinglePage(List<Widget> blocks) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 44, 56, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BookPageHeader(
            chapterLabel: widget.chapterLabel,
            chapterTitle: widget.chapterTitle,
            progressLabel: widget.progressLabel,
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: blocks,
              ),
            ),
          ),
          _buildBookFooter(),
        ],
      ),
    );
  }

  Widget _buildSpread(List<Widget> blocks) {
    // 호출부가 노드 경계를 알려줬으면 그 지점에서 자른다(왼쪽 1페이지 /
    // 오른쪽 2페이지). 안 알려줬으면 바록 개수 절반으로 나눐다.
    final split = (widget.spreadSplitIndex ?? (blocks.length / 2).ceil()).clamp(
      0,
      blocks.length,
    );
    final left = blocks.take(split).toList();
    final right = blocks.skip(split).toList();
    final rightIsOtherNode = widget.spreadSplitIndex != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(44, 36, 44, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BookPageHeader(
                  chapterLabel: widget.chapterLabel,
                  chapterTitle: widget.chapterTitle,
                  progressLabel: widget.progressLabel,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: left,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 가운데 접힘선 — 위아래로 사라지는 1px.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _ivory.withOpacity(0),
                _ivory.withOpacity(0.16),
                _ivory.withOpacity(0),
              ],
            ),
          ),
          child: const SizedBox(width: 1),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(44, 36, 44, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ⚠️ 오른쪽 쪽도 같은 헤더 위젯을 그린다(제목만 감춤) —
                // 높이를 숫자로 흉내 내면 글자 크기가 바뀔 때마다 좌우
                // 가름선과 첫 줄이 어긋난다.
                _BookPageHeader(
                  chapterLabel: rightIsOtherNode
                      ? widget.secondaryChapterLabel
                      : widget.chapterLabel,
                  chapterTitle: widget.chapterTitle,
                  progressLabel: rightIsOtherNode
                      ? widget.secondaryProgressLabel
                      : widget.progressLabel,
                  // 오른쪽이 같은 노드의 뒷부분이면 라벨·쪽번호를 다시 찍지
                  // 않는다(한 화에 하나). 다른 노드라면 그 노드의 표기를 보여줌다.
                  hideText: !rightIsOtherNode,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: right,
                    ),
                  ),
                ),
                _buildBookFooter(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 지면 아래 오른쪽에 붙는 액션 영역 — 선형은 "다음"/"완료", 인터랙티브는
  /// 선택지들이 그대로 들어온다.
  Widget _buildBookFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 20),
            color: _ivory.withOpacity(0.10),
          ),
          _buildSkipButton() ?? const SizedBox.shrink(),
          _buildActionArea(),
        ],
      ),
    );
  }

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

  /// 데스크톱 — 배경 이미지가 있으면 시네마틱(사진 전면 + 하단 스크림),
  /// 없으면 책 읽기 모드(가운데 지면)로 갈린다.
  ///
  /// 배경이 없는 노드에 그라디언트만 깔아 두면 "이미지가 로드 안 된 화면"처럼
  /// 보인다 — 애초에 사진이 없는 이야기는 책처럼 읽히는 편이 맞다.
  Widget _buildDesktopScene() {
    final url = widget.backgroundImageUrl;
    if (url == null || url.isEmpty) return _buildBookScene();
    return _buildCinematicScene(url);
  }

  Widget _buildCinematicScene(String url) {
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
              colors: [
                Color(0xF0000000),
                Color(0x8C000000),
                Colors.transparent,
              ],
              stops: [0.0, 0.34, 0.62],
            ),
          ),
        ),
        // ⚠️ 본문/액션은 Positioned가 아니라 Stack의 일반 자식으로 둔다 —
        // StackFit.expand가 이 자식에게 화면 전체 크기를 tight로 주므로
        // 하단 정렬(Column mainAxisAlignment.end)만으로 자리가 정해지고,
        // Positioned로 띄웠을 때처럼 크기·히트테스트가 애매해지지 않는다
        // (선택지가 보이는데 눌리지 않는 문제의 원인이었다).
        SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 60,
              right: rightInset,
              bottom: 40,
              top: 16,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _desktopReadingWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildSkipButton(),
                  ),
                ),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _desktopReadingWidth,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _buildVisibleBlocks(),
                      ),
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

        // 책 모드(배경 없는 지면)는 타이핑을 쓰지 않는다 — 책은 넘기면 지면이
        // 이미 인쇄돼 있는 게 자연스럽고, 두 쪽 펼침에서는 왼쪽을 다 찍은 뒤
        // 오른쪽이 시작해 대기가 두 배로 느껴졌다.
        if (completed || !_prefs.animationEnabled || _isBookMode) {
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
        fontSize: 15 * _prefs.fontScale,
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
      fontSize: 16 * _prefs.fontScale,
      // 배경 이미지가 없는 책 모드에서는 줄간격을 넓혀 읽는 밀도를 낮춘다.
      height: _isBookMode ? _bookLineHeight : 1.75,
      color: _bodyColor,
      fontFamily: fontFamily,
      fontFamilyFallback: const ['NotoSansKR'],
    );
  }

  /// 설정에서 고른 본문 글자 색 — 사진 위(시네마틱)에서는 대비가 필요해서
  /// 기본값일 때만 흰색으로 올린다. 사용자가 색을 직접 골랐으면 그 색을 쓴다.
  Color get _bodyColor {
    final option = ReaderPrefs.textColorOptions
        .where((o) => o.id == _prefs.textColorId)
        .firstOrNull;
    if (option == null || option.id == 'ivory') {
      return _isBookMode ? _ivory : Colors.white;
    }
    return Color(option.argb);
  }

  /// 데스크톱 폭 + 배경 이미지 없음 = 책 읽기 모드.
  bool get _isBookMode {
    final url = widget.backgroundImageUrl;
    return MediaQuery.sizeOf(context).width >= _desktopBreakpoint &&
        (url == null || url.isEmpty);
  }

  /// null을 반환하면 테마 기본값(번들된 NotoSansKR)을 그대로 쓴다.
  ///
  /// GoogleFonts.xxx()가 폰트를 등록하고 그 TextStyle의 fontFamily를 돌려준다 —
  /// 웹에서는 첫 진입에 잠깐 기본 폰트로 보이다 로딩이 끝나면 바뀐다.
  String? _fontFamilyFor(String fontId) {
    switch (fontId) {
      case 'nanum_gothic':
        return GoogleFonts.nanumGothic().fontFamily;
      case 'nanum_myeongjo':
        return GoogleFonts.nanumMyeongjo().fontFamily;
      case 'noto_serif':
        return GoogleFonts.notoSerifKr().fontFamily;
      default:
        return null;
    }
  }

  Widget _buildBottomSheet() {
    return _ReaderSettingsSheet(
      expanded: _sheetExpanded,
      onToggleExpanded: () => setState(() => _sheetExpanded = !_sheetExpanded),
      prefs: _prefs,
      ttsPlaying: _ttsPlaying,
      ttsLoading: _ttsLoading,
      onToggleTts: _toggleTtsPlayback,
      onBgmVolumeChanged: _handleBgmVolumeChanged,
      onBgmVolumeCommitted: _commitBgmVolume,
      onFontSelected: (fontId) => _updatePrefs(_prefs.copyWith(fontId: fontId)),
      onAnimationToggled: (enabled) =>
          _updatePrefs(_prefs.copyWith(animationEnabled: enabled)),
      onAutoContinueToggled: (enabled) =>
          _updatePrefs(_prefs.copyWith(ttsAutoContinueEnabled: enabled)),
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
        child: Icon(
          Icons.tune_rounded,
          color: _ivory.withOpacity(0.85),
          size: 21,
        ),
      ),
    );
  }
}

/// 데스크톱 설정 사이드바 — 하단 시트와 같은 컨트롤(TTS / BGM / 글꼴 /
/// 글자 애니메이션)을 같은 위젯([_SheetIconToggle], [_FontChip])으로 그린다.
/// 두 레이아웃이 각자 컨트롤을 들고 있다가 어긋나는 걸 막는다.
class _ReaderSettingsPanel extends StatelessWidget {
  final ReaderPrefs prefs;
  final bool simplified;
  final ValueChanged<double> onFontScaleSelected;
  final ValueChanged<String> onTextColorSelected;
  final bool ttsPlaying;
  final bool ttsLoading;
  final VoidCallback onClose;
  final VoidCallback onToggleTts;
  final ValueChanged<double> onBgmVolumeChanged;
  final ValueChanged<double> onBgmVolumeCommitted;
  final ValueChanged<String> onFontSelected;
  final ValueChanged<String> onPageModeSelected;
  final ValueChanged<bool> onAnimationToggled;
  final ValueChanged<bool> onAutoContinueToggled;

  const _ReaderSettingsPanel({
    required this.prefs,
    required this.simplified,
    required this.onFontScaleSelected,
    required this.onTextColorSelected,
    required this.ttsPlaying,
    required this.ttsLoading,
    required this.onClose,
    required this.onToggleTts,
    required this.onBgmVolumeChanged,
    required this.onBgmVolumeCommitted,
    required this.onFontSelected,
    required this.onPageModeSelected,
    required this.onAnimationToggled,
    required this.onAutoContinueToggled,
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
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ivory,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onClose,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: _ivory.withOpacity(0.55),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              // 선형 리더는 글꼴·글자 크기·쪽 보기만 — TTS/BGM/애니메이션은 감춘다.
              if (!simplified) ...[
                Row(
                  children: [
                    _SheetIconToggle(
                      icon: ttsLoading
                          ? Icons.hourglass_top_rounded
                          : (ttsPlaying
                                ? Icons.pause_circle_rounded
                                : Icons.play_circle_rounded),
                      label: ttsLoading
                          ? 'TTS 준비 중'
                          : (ttsPlaying ? 'TTS 켜짐' : 'TTS'),
                      active: ttsPlaying,
                      onTap: ttsLoading ? null : onToggleTts,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '배경음악 볼륨',
                  style: TextStyle(
                    fontSize: 13,
                    color: _ivory.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 8),
                _BgmVolumeRow(
                  volume: prefs.bgmMasterVolume,
                  onChanged: onBgmVolumeChanged,
                  onChangeEnd: onBgmVolumeCommitted,
                ),
                const SizedBox(height: 20),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white.withOpacity(0.08),
                ),
                const SizedBox(height: 20),
              ],
              Text(
                '글꼴',
                style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.8)),
              ),
              const SizedBox(height: 10),
              // 글꼴이 네 개라 320px 패널에서 한 줄로는 넘친다 — Wrap으로
              // 두 줄로 흘린다(칩 자체는 다른 설정과 같은 모양을 유지).
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _fontOptions)
                    _FontChip(
                      label: option.label,
                      selected: prefs.fontId == option.id,
                      onTap: () => onFontSelected(option.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '글자 크기',
                style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.8)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final option in ReaderPrefs.fontScaleOptions) ...[
                    _FontChip(
                      label: option.label,
                      selected: (prefs.fontScale - option.value).abs() < 0.001,
                      onTap: () => onFontScaleSelected(option.value),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '글자 색',
                style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.8)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final option in ReaderPrefs.textColorOptions) ...[
                    _ColorSwatch(
                      color: Color(option.argb),
                      label: option.label,
                      selected: prefs.textColorId == option.id,
                      onTap: () => onTextColorSelected(option.id),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              // 쪽 보기는 선형에만 — 인터랙티브는 배경 사진 위에 본문이 얹히는
              // 시네마틱 레이아웃이라 두 쪽으로 펼칠 지면 자체가 없다.
              if (simplified) ...[
                const SizedBox(height: 16),
                Text(
                  '쪽 보기',
                  style: TextStyle(
                    fontSize: 13,
                    color: _ivory.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final option in _pageModeOptions) ...[
                      _FontChip(
                        label: option.label,
                        selected: prefs.pageMode == option.id,
                        onTap: () => onPageModeSelected(option.id),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '배경 이미지가 없는 페이지에서만 두 쪽으로 펼칩니다',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.6,
                    color: _ivory.withOpacity(0.45),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (!simplified) ...[
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'TTS 자동 이어재생',
                        style: TextStyle(color: _ivory, fontSize: 12.5),
                      ),
                    ),
                    Switch(
                      value: prefs.ttsAutoContinueEnabled,
                      activeThumbColor: _gold,
                      onChanged: onAutoContinueToggled,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '켜면 내레이션이 끝날 때마다 다음 노드로 자동으로 넘어가요',
                  style: TextStyle(
                    fontSize: 11,
                    color: _ivory.withOpacity(0.45),
                  ),
                ),
              ],
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

/// 글꼴 선택지 — 'default'는 번들된 NotoSansKR, 나머지는 google_fonts가
/// 런타임에 받아 등록한다.
///
/// ⚠️ 예전엔 'serif'/'mono'가 'Georgia'/'Courier' 같은 시스템 폰트 이름을
/// 가리켰는데, Flutter 웹(CanvasKit)은 앱에 등록된 폰트만 그리기 때문에
/// 이름만 바뀌고 화면은 그대로였다(맑은 고딕처럼 OS에 깔린 폰트도 못 쓴다).
const List<({String id, String label})> _fontOptions = [
  (id: 'default', label: '본고딕'),
  (id: 'nanum_gothic', label: '나눔고딕'),
  (id: 'nanum_myeongjo', label: '나눔명조'),
  (id: 'noto_serif', label: '본명조'),
];

const List<({String id, String label})> _pageModeOptions = [
  (id: ReaderPrefs.pageModeSingle, label: '한 쪽'),
  (id: ReaderPrefs.pageModeSpread, label: '두 쪽'),
];

/// 책 모드 지면 상단 — 챕터 라벨 / 쪽번호 / 제목 / 가름선.
///
/// 두 쪽 펼침의 오른쪽 쪽은 [hideText]로 같은 위젯을 그대로 그리되
/// 보이는 글자만 감춘다(Visibility.maintainSize) — 높이를 숫자로 흉내 내면
/// 글자 크기가 바뀔 때마다 좌우 가름선과 첫 줄이 어긋난다. 쪽번호는 한
/// 페이지에 하나이므로 오른쪽에 다시 찍지 않는다.
class _BookPageHeader extends StatelessWidget {
  final String? chapterLabel;
  final String? chapterTitle;
  final String? progressLabel;
  final bool hideText;

  const _BookPageHeader({
    required this.chapterLabel,
    required this.chapterTitle,
    required this.progressLabel,
    this.hideText = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = chapterLabel;
    final title = chapterTitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (label != null && label.isNotEmpty)
              _Hideable(
                hidden: hideText,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: _gold.withOpacity(0.75),
                    fontFeatures: const [],
                  ),
                ),
              ),
            const Spacer(),
            if (progressLabel != null && progressLabel!.isNotEmpty)
              _Hideable(
                hidden: hideText,
                child: Text(
                  progressLabel!,
                  style: TextStyle(
                    fontSize: 11,
                    color: _ivory.withOpacity(0.4),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (title != null && title.isNotEmpty) ...[
          _Hideable(
            hidden: hideText,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _ivory,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          height: 1,
          margin: const EdgeInsets.only(bottom: 22),
          color: _ivory.withOpacity(0.12),
        ),
      ],
    );
  }
}

class _Hideable extends StatelessWidget {
  final bool hidden;
  final Widget child;

  const _Hideable({required this.hidden, required this.child});

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: !hidden,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: child,
    );
  }
}

class _ReaderSettingsSheet extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ReaderPrefs prefs;
  final bool ttsPlaying;
  final bool ttsLoading;
  final VoidCallback onToggleTts;
  final ValueChanged<double> onBgmVolumeChanged;
  final ValueChanged<double> onBgmVolumeCommitted;
  final ValueChanged<String> onFontSelected;
  final ValueChanged<bool> onAnimationToggled;
  final ValueChanged<bool> onAutoContinueToggled;

  const _ReaderSettingsSheet({
    required this.expanded,
    required this.onToggleExpanded,
    required this.prefs,
    required this.ttsPlaying,
    required this.ttsLoading,
    required this.onToggleTts,
    required this.onBgmVolumeChanged,
    required this.onBgmVolumeCommitted,
    required this.onFontSelected,
    required this.onAnimationToggled,
    required this.onAutoContinueToggled,
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
        height: expanded ? 292 : 26,
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
                        _SheetIconToggle(
                          icon: ttsLoading
                              ? Icons.hourglass_top_rounded
                              : (ttsPlaying
                                    ? Icons.pause_circle_rounded
                                    : Icons.play_circle_rounded),
                          label: ttsLoading
                              ? 'TTS 준비 중'
                              : (ttsPlaying ? 'TTS 켜짐' : 'TTS'),
                          active: ttsPlaying,
                          onTap: ttsLoading ? null : onToggleTts,
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'TTS 자동 이어재생',
                          style: TextStyle(color: _ivory, fontSize: 12.5),
                        ),
                        const Spacer(),
                        Switch(
                          value: prefs.ttsAutoContinueEnabled,
                          activeThumbColor: _gold,
                          onChanged: onAutoContinueToggled,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _BgmVolumeRow(
                      volume: prefs.bgmMasterVolume,
                      onChanged: onBgmVolumeChanged,
                      onChangeEnd: onBgmVolumeCommitted,
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
  final VoidCallback? onTap;

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
            Icon(
              icon,
              color: active ? _gold : _ivory.withOpacity(0.5),
              size: 26,
            ),
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

/// BGM 볼륨 슬라이더 — 데스크톱 사이드바/모바일 하단 시트가 같은 위젯을
/// 공유한다(다른 설정들이 [_SheetIconToggle]/[_FontChip]을 공유하는 것과
/// 같은 이유). 왼쪽 스피커 아이콘은 탭하면 0%/100%를 오가는 빠른 음소거
/// 토글이다("다시 보지 않기" 같은 정밀한 이전 값 기억은 없다 — 이 화면
/// 인스턴스는 노드가 바뀔 때마다 다시 만들어져서 그 사이의 로컬 상태를
/// 유지할 수 없으므로, 값을 "기억"하는 대신 그냥 0 또는 1로 단순하게
/// 오간다). [onChanged]는 드래그하는 동안(그리고 음소거 토글 탭 시) 매번
/// 불려 [AudioService]에 즉시 반영되고, [onChangeEnd]는 손을 뗀 시점(또는
/// 토글 탭 직후)에 한 번만 불려 Firestore에 저장된다.
class _BgmVolumeRow extends StatelessWidget {
  final double volume;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BgmVolumeRow({
    required this.volume,
    required this.onChanged,
    required this.onChangeEnd,
  });

  void _toggleMute() {
    final next = volume > 0 ? 0.0 : 1.0;
    onChanged(next);
    onChangeEnd(next);
  }

  @override
  Widget build(BuildContext context) {
    final muted = volume <= 0;
    return Row(
      children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggleMute,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              muted ? Icons.music_off_rounded : Icons.music_note_rounded,
              color: muted ? _ivory.withOpacity(0.45) : _gold,
              size: 22,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _gold,
              thumbColor: _gold,
              inactiveTrackColor: Colors.white.withOpacity(0.14),
              trackHeight: 3,
              overlayColor: _gold.withOpacity(0.15),
            ),
            child: Slider(
              value: volume.clamp(0.0, 1.0),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${(volume * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: _ivory.withOpacity(0.85)),
          ),
        ),
      ],
    );
  }
}

/// 글자 색 선택 — 색 자체가 보기여야 하므로 칩 대신 색 원이다.
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _gold : Colors.white.withOpacity(0.18),
                  width: selected ? 2 : 1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? _gold : _ivory.withOpacity(0.6),
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

  const _FontChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _gold.withOpacity(0.18)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? _gold.withOpacity(0.6)
                : Colors.white.withOpacity(0.12),
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
