import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/story/background_image_inheritance.dart';
import '../data/admin_bgm_repository.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_sfx_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/admin_tts_voice_repository.dart';
import '../data/node_edit_session_cache.dart';
import '../data/node_id_suggestion.dart';
import '../models/admin_bgm.dart';
import '../models/admin_image.dart';
import '../models/admin_sfx.dart';
import '../models/admin_story_node.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_story_pack.dart';
import '../models/admin_tts_voice.dart';
import '../models/pending_action.dart';
import '../models/story_pack_type.dart';
import '../widgets/admin_theme.dart';
import '../widgets/bulk_node_writer.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/labeled_field.dart';
import '../widgets/node_editor.dart';
import '../widgets/story_map_view.dart';
import '../widgets/story_node_sidebar.dart';

/// "노드별로 쓰기"(사이드바+에디터, 기본) / "한 번에 쓰기"(BulkNodeWriter,
/// linear 팩 전용) / "구조 보기"(StoryMapView) — 셋 중 하나만 보인다.
enum _ViewMode { single, bulk, map }

/// [AdminStoryNode](세션 캐시나 fetchNode로 얻은 전체 문서)를 사이드바용
/// 요약으로 압축한다 — 캐시에 있는 노드를 표시 목록에 끼워 넣을 때(신규
/// 초안이든, 손댄 기존 노드든) 공통으로 쓴다.
AdminStoryNodeSummary summaryFromNode(AdminStoryNode node) {
  return AdminStoryNodeSummary(
    id: node.id,
    preview: node.previewText,
    status: node.status,
    pendingAction: node.pendingAction,
    order: node.order,
    backgroundImageId: node.backgroundImageId,
    backgroundAppliesForward: node.backgroundAppliesForward,
    hasLiveSnapshot: !node.isNew,
    choices: node.choices,
    nextNodeId: node.nextNodeId,
  );
}

/// "스토리 노드" 탭. 사이드바(노드 목록) + 노드 편집 폼을 이어 붙이고,
/// 임시저장/승인요청/삭제/승인취소 같은 실제 Firestore 쓰기 동작을 담당한다.
///
/// 선택된 노드는 [_editingNode]에 로컬 가변 복사본으로 들고 있다가 명시적으로
/// 저장할 때만 Firestore에 반영한다 — 그 사이에 서버 스트림이 갱신돼도
/// 지금 타이핑 중인 내용을 덮어쓰지 않기 위해서다(story_editor_prototype.html이
/// 브라우저 메모리 하나만 썼던 것과 같은 이유).
class StoryTabView extends StatefulWidget {
  final String packId;

  /// pack.type에 따라 NodeEditor 하단이 선택지 목록/다음 노드 입력으로
  /// 갈리고, pack.defaultBackgroundImage는 어떤 노드도 배경을 명시적으로
  /// 안 골랐을 때의 최종 폴백이다(lib/core/story/
  /// background_image_inheritance.dart). 부모(AuthorToolPage)가 이미 들고
  /// 있는 AdminStoryPack을 통째로 내려받는다 — 팩 목록 스트림이 갱신되면
  /// 부모가 새 pack 값으로 이 위젯을 다시 만들어 준다.
  final AdminStoryPack pack;
  final AdminStoryRepository repository;
  final AdminImageRepository imageRepository;
  final AdminSfxRepository sfxRepository;
  final AdminBgmRepository bgmRepository;
  final AdminTtsVoiceRepository ttsVoiceRepository;

  /// 저장 안 한 편집 내용의 세션 캐시 — AuthorToolPage가 소유해서 팩 전환/탭
  /// 전환에도 살아남는다(자세한 설명은 node_edit_session_cache.dart 참고).
  /// 이 위젯 자신은 팩이 바뀔 때마다 통째로 재생성되므로, 캐시를 여기 State
  /// 안에 두면 전환할 때마다 사라져 버린다 — 그래서 부모가 만든 걸 그대로
  /// 받아 쓴다.
  final NodeEditSessionCache sessionCache;

  const StoryTabView({
    super.key,
    required this.packId,
    required this.pack,
    required this.repository,
    required this.imageRepository,
    required this.sfxRepository,
    required this.bgmRepository,
    required this.ttsVoiceRepository,
    required this.sessionCache,
  });

  @override
  State<StoryTabView> createState() => _StoryTabViewState();
}

class _StoryTabViewState extends State<StoryTabView> {
  /// State가 살아있는 동안(= 지금 이 packId로 고정된 동안, StoryTabView는
  /// author_tool_page.dart에서 packId별로 다른 Key를 받아 팩을 바꿀 때마다
  /// 통째로 재생성된다) 딱 한 번만 만든다. build()에서 매번 새로 호출하면
  /// (예전 코드가 그랬다) 키 입력 한 번마다(onChanged → setState) watchNodeSummaries가
  /// 새 Firestore 리스너를 새로 열고 StreamBuilder가
  /// 구독을 끊었다 다시 맺으면서 사이드바가 깜빡였다 — author_tool_page.dart의
  /// _packsStream, approvals_tab.dart의 _pendingStream과 같은 이유로 같은
  /// 패턴을 따른다.
  late final Stream<List<AdminStoryNodeSummary>> _nodeSummariesStream = widget
      .repository
      .watchNodeSummaries(widget.packId);

  /// 이미지 라이브러리는 팩과 무관하게 공유되지만(FIRESTORE_SCHEMA.md), 같은
  /// 이유로 build()에서 매번 새로 구독하지 않는다.
  late final Stream<List<AdminImage>> _imagesStream = widget.imageRepository
      .watchImages();

  /// 효과음 라이브러리도 이미지와 같은 이유로(팩과 무관하게 공유, build()마다
  /// 새로 구독하지 않음) 한 번만 만든다.
  late final Stream<List<AdminSfx>> _sfxLibraryStream = widget.sfxRepository
      .watchSfxLibrary();

  /// 배경음악 라이브러리도 이미지/효과음과 같은 이유로 한 번만 만든다.
  late final Stream<List<AdminBgm>> _bgmLibraryStream = widget.bgmRepository
      .watchBgmLibrary();

  /// Typecast 보이스 캐시(ttsVoiceCache/typecast)도 팩과 무관하게 공유되므로
  /// 같은 이유로 한 번만 구독한다 — 실제 값 채우기는 서버(예약 실행/수동
  /// 새로고침)만 하고, 여기선 그 결과를 읽기만 한다.
  late final Stream<List<AdminTtsVoice>> _ttsVoicesStream = widget
      .ttsVoiceRepository
      .watchVoices();

  /// [TtsVoicePickerField]의 새로고침 버튼이 누르는 동안 스피너로 바꿔서
  /// 중복 클릭을 막는다 — bgmLibrary/sfxLibrary는 새로고침 버튼이 아예 없어서
  /// (그쪽은 라이브러리 자체를 관리자가 직접 채우므로) 대응하는 상태가
  /// 없었다.
  bool _refreshingTtsVoices = false;

  Future<void> _handleRefreshTtsVoices() async {
    if (_refreshingTtsVoices) return;
    setState(() => _refreshingTtsVoices = true);
    try {
      await widget.ttsVoiceRepository.refreshVoices();
    } catch (e) {
      // pack_settings_page.dart의 같은 핸들러와 같은 이유 — catch 없이
      // finally만 있으면 실패가 조용히 사라져서 "호출이 됐는지조차" 알 수
      // 없었다.
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('보이스 목록 새로고침에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _refreshingTtsVoices = false);
    }
  }

  String? _selectedNodeId;
  AdminStoryNode? _editingNode;
  bool _autoSelectAttempted = false;

  /// [_refreshUnsubmittedNodes]가 채우는, "이 팩에서 Firestore엔 이미
  /// 임시저장돼 있지만(pendingAction == null) 세션 캐시엔 없는" 노드 중
  /// liveSnapshot과 실제로 다른 것들 — [_refreshUnsubmittedNodes] doc 참고.
  /// **세션 캐시에 있는 노드는 여기 안 들어간다** — 그쪽은 Firestore 조회가
  /// 필요 없어서 [_cachedUnsubmittedNodes]가 매번 즉시 다시 계산한다(아래).
  /// "변경사항 전체 승인요청" 버튼의 개수/제출 대상은 [_allUnsubmittedNodes]가
  /// 이 필드와 [_cachedUnsubmittedNodes]를 합쳐서 만든다.
  List<AdminStoryNode> _persistedUnsubmittedNodes = const [];
  bool _isRefreshingUnsubmitted = false;
  bool _unsubmittedFirstLoadAttempted = false;

  /// build()의 StreamBuilder 안에서만 새로 계산되는 rawSummaries를
  /// [_refreshUnsubmittedNodes] 같은 인스턴스 메서드에서도 참조할 수 있게
  /// 매 build마다 여기 복사해 둔다.
  List<AdminStoryNodeSummary> _lastRawSummaries = const [];

  _ViewMode _viewMode = _ViewMode.single;

  /// 스토리맵에서 "+" 드래그로 빈 캔버스에 놓아 지금 편집 중인 노드가 방금
  /// 만들어졌을 때만 값이 있다 — 그 출발 노드 id. NodeEditor 헤더의 컨텍스트
  /// 라인에 쓰인다. [_creationSourceChoiceIndex]와 짝을 이룬다(interactive
  /// 팩에서만 값이 있다 — 그 출발 노드의 choices 배열 안, 이 노드를 향해
  /// 방금 만들어진 선택지의 인덱스). 둘 다 [_selectNode]가 명시적으로
  /// 넘겨줄 때만 세팅되고, 다른 경로(사이드바 클릭, 맵에서 노드 박스 탭 등)로
  /// 노드를 선택하면 자동으로 null로 리셋된다.
  String? _creationSourceId;
  int? _creationSourceChoiceIndex;

  /// 사이드바의 "선택 삭제" 체크박스 선택 상태 — 편집 중인 노드 선택
  /// (_selectedNodeId)과는 별개의 축이다(하나는 "지금 뭘 편집 중인가", 다른
  /// 하나는 "일괄 삭제 후보로 뭘 골랐는가").
  final Set<String> _bulkDeleteSelection = {};

  /// 세션 캐시(widget.sessionCache)에 이 노드의 저장 안 한 편집 내용이
  /// 있으면 그걸 그대로 복원한다 — Firestore에서 새로 읽어오면 방금까지
  /// 타이핑하던 내용이 사라진다. 캐시에 없을 때만 실제로 fetchNode()한다.
  Future<void> _selectNode(
    String nodeId, {
    String? creationSourceId,
    int? creationSourceChoiceIndex,
  }) async {
    final cached = widget.sessionCache.get(widget.packId, nodeId);
    if (cached != null) {
      setState(() {
        _selectedNodeId = nodeId;
        _editingNode = cached;
        _creationSourceId = creationSourceId;
        _creationSourceChoiceIndex = creationSourceChoiceIndex;
      });
      return;
    }

    final node = await widget.repository.fetchNode(widget.packId, nodeId);
    if (!mounted || node == null) return;
    setState(() {
      _selectedNodeId = nodeId;
      _editingNode = node;
      _creationSourceId = creationSourceId;
      _creationSourceChoiceIndex = creationSourceChoiceIndex;
    });
  }

  /// [_editingNode]는 명시적으로 저장할 때만 Firestore에 반영되는 로컬 가변
  /// 복사본이다(클래스 상단 doc 참고) — 그래서 다른 화면(admin 승인 대기함)에서
  /// 이 노드를 승인/반려해도 [_nodeSummariesStream]은 라이브로 갱신되지만
  /// [_editingNode].status/pendingAction/liveSnapshot은 이 메서드가 없으면
  /// F5 전까지 계속 낡은 값을 들고 있는다.
  ///
  /// status/pendingAction만 부분적으로 덮어쓰는 대신 [_selectNode]로 통째로
  /// 다시 읽어오는 이유: liveSnapshot의 실제 내용(승인 시점 콘텐츠 스냅샷)은
  /// 다음 saveNode() 호출이 Firestore 규칙의 "liveSnapshot 불변" 조건을
  /// 통과하려면 서버 값과 정확히 같아야 한다 — 목록 스트림은 liveSnapshot
  /// 유무만 알고 내용은 모르므로, 내용까지 필요한 경우엔 결국 fetchNode()가
  /// 필요하다. 요약과 어긋난 게 없으면(가장 흔한 경우) 아무 것도 하지 않는다.
  ///
  /// 세션 캐시에 저장 안 한 편집 내용이 있으면 건너뛴다 — 그 사이 서버
  /// 스냅샷이 와도 편집 중인 내용을 덮어쓰지 않기 위해서다. 캐시가 비워지는
  /// 다음 빌드(저장하거나, 다른 노드로 옮겼다 돌아오거나)에서 다시 시도된다.
  void _syncEditingNodeWithLiveSummary(
    AdminStoryNode? editingNode,
    List<AdminStoryNodeSummary> summaries,
  ) {
    if (editingNode == null) return;
    // 세션 캐시에 있으면 건너뛴다 — 저장 안 한 편집 내용이 있다는 뜻이고,
    // 한 번도 저장 안 한 신규 초안(_handleAddNode가 만들자마자 캐시에 넣는다)도
    // 항상 여기 걸린다.
    if (widget.sessionCache.has(widget.packId, editingNode.id)) return;

    AdminStoryNodeSummary? liveSummary;
    for (final summary in summaries) {
      if (summary.id == editingNode.id) {
        liveSummary = summary;
        break;
      }
    }

    if (liveSummary == null) {
      // 다른 화면에서 삭제 요청이 승인되어 노드 자체가 사라졌다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _selectedNodeId != editingNode.id ||
            widget.sessionCache.has(widget.packId, editingNode.id)) {
          return;
        }
        setState(() {
          _selectedNodeId = null;
          _editingNode = null;
        });
      });
      return;
    }

    final outOfSync =
        liveSummary.status != editingNode.status ||
        liveSummary.pendingAction != editingNode.pendingAction ||
        liveSummary.hasLiveSnapshot == editingNode.isNew;
    if (!outOfSync) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _selectedNodeId != editingNode.id ||
          widget.sessionCache.has(widget.packId, editingNode.id)) {
        return;
      }
      _selectNode(editingNode.id);
    });
  }

  /// [existing]은 반드시 Firestore에 실제로 저장된 노드 목록(rawSummaries)이어야
  /// 한다 — 사이드바 표시용으로 미저장 초안을 끼워 넣은 목록을 넘기면,
  /// suggestSequentialNodeIds가 그 초안을 이미 존재하는 노드로 세어 다음
  /// "+" 클릭 때 번호를 하나 건너뛴다(실제로 겪은 버그 — story_tab_view.dart의
  /// build()에서 rawSummaries/displaySummaries를 분리해 두는 이유). 세션
  /// 캐시에만 있는(아직 저장 안 한) 신규 노드 id도 같이 피해야 한다 — 안
  /// 그러면 "+"를 두 번 눌렀을 때 첫 번째로 만든 미저장 초안과 같은 id를
  /// 다시 제안해서 그 초안을 덮어써 버린다.
  /// linear 팩의 "지금 체인의 마지막 노드" — nextNodeId가 비어 있는 노드
  /// 중 order가 가장 큰 것. order는 이미 이 메서드 바로 아래(nextOrder
  /// 계산)와 배경 이미지 인계/사이드바 정렬에서 "지금까지 만들어진 순서"를
  /// 나타내는 값으로 쓰이고 있어서 그 개념을 그대로 재사용한다 — 새로운
  /// 순회 규칙을 따로 만들지 않는다. nextNodeId가 비어 있는 노드가 여러
  /// 개면(체인이 어딘가 끊겨 있는 등 이례적인 경우) order가 가장 큰 쪽을
  /// "마지막"으로 본다. 하나도 없으면(모든 노드가 이미 연결돼 있음) null —
  /// 자동으로 이을 대상이 없다는 뜻이다.
  AdminStoryNodeSummary? _findLastLinearNode(
    List<AdminStoryNodeSummary> existing,
  ) {
    AdminStoryNodeSummary? last;
    for (final n in existing) {
      final next = n.nextNodeId;
      if (next != null && next.isNotEmpty) continue;
      if (last == null || n.order > last.order) last = n;
    }
    return last;
  }

  Future<void> _handleAddNode(List<AdminStoryNodeSummary> existing) async {
    final takenIds = {
      ...existing.map((n) => n.id),
      ...widget.sessionCache.nodeIdsForPack(widget.packId),
    };
    final candidateId = suggestSequentialNodeIds(takenIds, 1).first;

    // 새 노드는 기본적으로 맨 뒤에 이어 쓰는 경우가 대부분이라, 다음 순서로
    // 자동 배정한다 — 배경 이미지 인계가 바로 동작하게 하려는 것(0으로
    // 고정하면 항상 맨 앞으로 끼어들어 인계 규칙이 매번 어긋난다).
    final nextOrder = existing.isEmpty
        ? 0
        : existing.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;

    final node = AdminStoryNode(id: candidateId, order: nextOrder);
    // 만들자마자 세션 캐시에 넣는다 — 아무것도 안 쳐도 이 초안은 "존재"하고,
    // 다른 노드로 옮겼다 돌아와도(또는 팩/탭을 오가도) 그대로 남아있어야 한다.
    widget.sessionCache.put(widget.packId, node);

    // linear 팩은 "맨 뒤에 이어 쓰기"가 압도적으로 흔한 경우라, 새 노드를
    // 만들 때 기존 체인의 마지막 노드를 자동으로 이 새 노드에 연결해 둔다
    // — 매번 "다음 노드" 후보 목록에서 수동으로 골라 잇는 수고를 없앤다.
    // interactive 팩은 하지 않는다 — 새 노드가 아직 아무 데도 안 이어진
    // 채(나중에 선택지 대상으로 고를) 있는 게 정상적인 경우가 많아서,
    // 자동으로 이어 붙이면 오히려 방해가 된다.
    String? autoLinkedSourceId;
    if (widget.pack.type == StoryPackType.linear) {
      final lastNode = _findLastLinearNode(existing);
      if (lastNode != null) {
        final previousNode =
            widget.sessionCache.get(widget.packId, lastNode.id) ??
            await widget.repository.fetchNode(widget.packId, lastNode.id);
        if (mounted && previousNode != null) {
          previousNode.nextNodeId = node.id;
          widget.sessionCache.put(widget.packId, previousNode);
          autoLinkedSourceId = previousNode.id;
        }
      }
    }
    if (!mounted) return;

    setState(() {
      _selectedNodeId = node.id;
      _editingNode = node;
      // _creationSourceId를 설정해 두면, 이 새 노드를 저장/승인요청할 때
      // _persistCreationSourceEdgeIfNeeded가 방금 자동으로 이어붙인 이전
      // 노드도 같이(항상 임시저장으로만) 저장해 준다 — 구조보기에서 선택지로
      // 새 노드를 만들 때와 완전히 같은 메커니즘을 그대로 재사용하는 것이지,
      // 별도의 저장 경로를 새로 만드는 게 아니다. choiceIndex는 남겨 두지
      // 않는다(null이면 _fillCreationChoiceLabelIfNeeded가 자연히 아무것도
      // 안 한다 — linear는 "선택지 문구" 개념이 없다).
      _creationSourceId = autoLinkedSourceId;
      _creationSourceChoiceIndex = null;
    });
    unawaited(_refreshUnsubmittedNodes());
  }

  /// 사이드바 드래그 재정렬 — [displayed]는 지금 화면에 보이는 순서 그대로의
  /// 목록(order로 정렬된 displaySummaries)이다. 옮긴 자리를 반영해 순서를
  /// 다시 매기고, order가 실제로 바뀐 노드만 세션 캐시에 반영한다 — 다른
  /// 편집과 똑같이 "임시저장"/"승인 요청 보내기"를 눌러야 Firestore에
  /// 반영되는 초안일 뿐, 드래그만으로 즉시 쓰지 않는다.
  ///
  /// 배경 이미지 인계 체인(lib/core/story/background_image_inheritance.dart)은
  /// order를 기준으로 매 build마다 다시 계산되므로, 여기서 order만 바꿔
  /// 두면 재정렬 직후 미리보기에 곧바로 반영된다 — 별도로 인계 값을
  /// 다시 계산해 넣을 필요가 없다.
  Future<void> _handleReorder(
    List<AdminStoryNodeSummary> displayed,
    int oldIndex,
    int newIndex,
  ) async {
    // ReorderableListView의 관례: 아래로 옮길 때 newIndex는 옮기는 항목을
    // 뺀 목록 기준이라, oldIndex보다 크면 1을 빼야 실제 삽입 위치가 된다.
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final reordered = List<AdminStoryNodeSummary>.from(displayed);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    var changed = false;
    for (var i = 0; i < reordered.length; i++) {
      final summary = reordered[i];
      if (summary.order == i) continue;

      // 지금 편집 중인 바로 그 객체라면 그 인스턴스를 그대로 고친다 —
      // 그래야 에디터가 들고 있는 참조와 캐시에 들어가는 참조가 갈라지지
      // 않는다. 아니라면 캐시에서, 그것도 없으면 Firestore에서 가져온다.
      AdminStoryNode? node = _editingNode?.id == summary.id
          ? _editingNode
          : null;
      node ??= widget.sessionCache.get(widget.packId, summary.id);
      node ??= await widget.repository.fetchNode(widget.packId, summary.id);
      if (!mounted) return;
      if (node == null) continue;

      node.order = i;
      widget.sessionCache.put(widget.packId, node);
      changed = true;
    }

    if (!mounted || !changed) return;
    setState(() {});
  }

  /// "한 번에 쓰기" 저장 — 페이지 수만큼 초안 노드를 만들어 순서대로
  /// nextNodeId로 이어 붙이고, 한 번의 배치 쓰기로 전부 만든 뒤 바로 승인
  /// 요청까지 보낸다("승인 없이 반영되지 않는다"는 원칙은 그대로 유지 —
  /// pendingAction: create일 뿐 status는 여전히 draft다).
  Future<void> _handleBulkSave(
    List<BulkPagePreview> pages,
    List<AdminStoryNodeSummary> existing,
  ) async {
    if (pages.isEmpty) return;

    final confirmed = await showConfirmDialog(
      context,
      '${pages.length}개 노드를 만들어 승인 요청을 보낼까요? 상위 관리자가 승인해야 플레이어에게 보여요.',
    );
    if (!confirmed || !mounted) return;

    final ids = suggestSequentialNodeIds(
      existing.map((n) => n.id),
      pages.length,
    );
    final startOrder = existing.isEmpty
        ? 0
        : existing.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;

    final nodes = <AdminStoryNode>[];
    for (var i = 0; i < pages.length; i++) {
      final node = AdminStoryNode(
        id: ids[i],
        order: startOrder + i,
        bodyText: pages[i].text,
        nextNodeId: i < pages.length - 1 ? ids[i + 1] : null,
        pendingAction: PendingAction.create,
      );
      node.applyBodyTextToBlocks();
      nodes.add(node);
    }

    await widget.repository.saveNodesBatch(widget.packId, nodes);
    for (final node in nodes) {
      // ← 추가
      await widget.repository.stampApprovalRequestedAt(
        widget.packId,
        node.id,
      ); // ← 추가
    }

    if (!mounted) return;

    setState(() => _viewMode = _ViewMode.single);
    _showToast(context, '${nodes.length}개 노드를 만들어 승인 요청을 보냈어요 ✓');
  }

  /// [rawSummaries]는 반드시 Firestore에 실제로 저장된 노드 목록이어야 한다
  /// — "이 nodeId가 한 번이라도 저장된 적 있는지"를 여기서 직접 판단하기
  /// 때문이다(세션 캐시에만 있는 신규 초안은 지울 Firestore 문서 자체가
  /// 없다). 지금 편집 화면에 열려 있는 것이든, 다른 노드로 옮겼다가 사이드바
  /// 목록에서 바로 지우는 것이든 똑같이 다룬다.
  Future<void> _handleDeleteNode(
    String nodeId,
    List<AdminStoryNodeSummary> rawSummaries,
  ) async {
    final isPersisted = rawSummaries.any((s) => s.id == nodeId);

    if (!isPersisted) {
      final confirmed = await showConfirmDialog(
        context,
        '아직 발행된 적 없는 초안이에요. 바로 삭제할까요?',
      );
      if (!confirmed || !mounted) return;
      widget.sessionCache.remove(widget.packId, nodeId);
      if (_selectedNodeId == nodeId) {
        setState(() {
          _selectedNodeId = null;
          _editingNode = null;
        });
      } else {
        setState(() {});
      }
      unawaited(_refreshUnsubmittedNodes());
      return;
    }

    // 지금 편집 화면에 없더라도, 예전에 열어서 손대 놓고 저장 안 한 채로 지우는
    // 경우일 수 있다 — 캐시에 남아있으면 지운 노드가 다시 "수정됨"으로
    // 보이는 유령 항목이 된다.
    widget.sessionCache.remove(widget.packId, nodeId);

    final node = await widget.repository.fetchNode(widget.packId, nodeId);
    if (!mounted || node == null) return;

    if (node.liveSnapshot == null) {
      final confirmed = await showConfirmDialog(
        context,
        '아직 발행된 적 없는 초안이에요. 바로 삭제할까요?',
      );
      if (!confirmed || !mounted) return;
      await widget.repository.deleteNodeDoc(widget.packId, nodeId);
      if (!mounted) return;
      if (_selectedNodeId == nodeId) {
        setState(() {
          _selectedNodeId = null;
          _editingNode = null;
        });
      }
      unawaited(_refreshUnsubmittedNodes());
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      '이미 연재 중인 노드예요. 삭제 요청을 보낼까요? 상위 관리자가 승인하기 전까지는 계속 플레이어에게 그대로 보여요.',
    );
    if (!confirmed || !mounted) return;

    node.pendingAction = PendingAction.delete;
    node.dirty = false;
    await widget.repository.saveNode(widget.packId, node);
    await widget.repository.stampApprovalRequestedAt(
      widget.packId,
      node.id,
    ); // ← 추가
    if (!mounted) return;

    if (_selectedNodeId == nodeId) {
      setState(() {
        _editingNode = node;
      });
    }
    unawaited(_refreshUnsubmittedNodes());
  }

  void _toggleBulkDeleteSelect(String id) {
    setState(() {
      if (!_bulkDeleteSelection.remove(id)) _bulkDeleteSelection.add(id);
    });
  }

  void _toggleBulkDeleteSelectAll(List<AdminStoryNodeSummary> summaries) {
    setState(() {
      if (summaries.isNotEmpty &&
          _bulkDeleteSelection.length == summaries.length) {
        _bulkDeleteSelection.clear();
      } else {
        _bulkDeleteSelection
          ..clear()
          ..addAll(summaries.map((s) => s.id));
      }
    });
  }

  /// 선택 중에 발행된 적 없는 초안과 이미 연재 중인 노드가 섞여 있으면 자동으로
  /// 나눠 처리한다 — 초안은 그 자리에서 바로 지우고, 연재 중인 노드는 단건
  /// 삭제 버튼과 같은 삭제 요청(pendingAction: delete)만 걸어 둔다. 혼재된
  /// 선택을 통째로 막는 대신 이렇게 자동으로 나누는 쪽을 택했다 — "일부는 요청이
  /// 필요하다"는 이유로 이미 발행된 적 없는 나머지 노드까지 못 지우게 막는 건
  /// 불필요한 마찰이라고 판단했다. 대신 끝나고 나서 뭐가 즉시 지워졌고 뭐가
  /// 요청만 걸렸는지 요약으로 보여준다.
  Future<void> _handleBulkDelete() async {
    final ids = _bulkDeleteSelection.toList();
    if (ids.isEmpty) return;

    final confirmed = await showConfirmDialog(
      context,
      '${ids.length}개 노드를 삭제할까요? 발행된 적 없는 노드는 즉시 삭제되고, 이미 연재 중인 노드는 '
      '삭제 요청이 들어가 상위 관리자 승인 후 삭제돼요.',
    );
    if (!confirmed || !mounted) return;

    var deletedImmediately = 0;
    var requestedForApproval = 0;
    var failed = 0;
    var clearedEditingSelection = false;

    for (final id in ids) {
      try {
        widget.sessionCache.remove(widget.packId, id);

        // 세션 캐시에만 있던(한 번도 저장 안 한) 초안이면 fetchNode가
        // null을 반환한다 — 지울 Firestore 문서 자체가 없으니 그걸로 끝.
        final node = await widget.repository.fetchNode(widget.packId, id);
        if (node == null) {
          deletedImmediately += 1;
          if (_selectedNodeId == id) clearedEditingSelection = true;
          continue;
        }

        if (node.liveSnapshot == null) {
          await widget.repository.deleteNodeDoc(widget.packId, id);
          deletedImmediately += 1;
        } else {
          node.pendingAction = PendingAction.delete;
          node.dirty = false;
          await widget.repository.saveNode(widget.packId, node);
          await widget.repository.stampApprovalRequestedAt(
            widget.packId,
            node.id,
          ); // ← 추가
          requestedForApproval += 1;
        }

        if (_selectedNodeId == id) clearedEditingSelection = true;
      } catch (_) {
        failed += 1;
      }
    }

    if (!mounted) return;
    setState(() {
      _bulkDeleteSelection.clear();
      if (clearedEditingSelection) {
        _selectedNodeId = null;
        _editingNode = null;
      }
    });

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AdminColors.panel,
        title: Text('일괄 삭제 완료', style: TextStyle(color: AdminColors.ivory)),
        content: Text(
          '즉시 삭제 $deletedImmediately개 · 삭제 요청 $requestedForApproval개'
          '${failed > 0 ? ' · 실패 $failed개' : ''}',
          style: TextStyle(color: AdminColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인', style: TextStyle(color: AdminColors.gold)),
          ),
        ],
      ),
    );
  }

  /// 스토리맵에서 "+" 드래그로 빈 캔버스에 놓아 만들어진 노드를 저장할
  /// 때만 동작한다([_creationSourceId]/[_creationSourceChoiceIndex]가 둘 다
  /// 있을 때) — 드롭 순간엔 타이핑할 틈이 없어서 출발 노드에 걸린 선택지의
  /// 문구가 비어 있을 수 있다(story_map_choice_popover_spec.md). 그 문구가
  /// 아직 비어 있으면 저장 직전에 한 번 물어본다. "나중에"를 골라도 저장은
  /// 그대로 진행된다 — 저장을 막는 관문이 아니라 놓치기 쉬운 빈칸을 짚어
  /// 주는 안내일 뿐이다.
  Future<void> _fillCreationChoiceLabelIfNeeded() async {
    final sourceId = _creationSourceId;
    final choiceIndex = _creationSourceChoiceIndex;
    if (sourceId == null || choiceIndex == null) return;

    final sourceNode =
        widget.sessionCache.get(widget.packId, sourceId) ??
        await widget.repository.fetchNode(widget.packId, sourceId);
    if (!mounted ||
        sourceNode == null ||
        choiceIndex >= sourceNode.choices.length) {
      return;
    }
    if (sourceNode.choices[choiceIndex].label.trim().isNotEmpty) return;

    final label = await _promptChoiceLabel();
    if (!mounted || label == null || label.trim().isEmpty) return;

    sourceNode.choices[choiceIndex].label = label.trim();
    widget.sessionCache.put(widget.packId, sourceNode);
  }

  Future<String?> _promptChoiceLabel() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AdminColors.panel,
        title: Text(
          '이 노드로 연결한 선택지 문구를 입력해주세요',
          style: TextStyle(color: AdminColors.ivory, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AdminColors.inputText),
          decoration: adminInputDecoration(hintText: '예: 문을 연다'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('나중에', style: TextStyle(color: AdminColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.gold,
              foregroundColor: Colors.white,
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// 임시저장의 핵심 로직 — Firestore에 쓰고 세션 캐시에서 지운다. 개별
  /// 패널의 "임시저장" 버튼([_handleSaveDraft])과 그래프 화면의 "전체
  /// 임시저장"([_handleBulkSaveDraftAll])이 둘 다 이 메서드 하나를 그대로
  /// 쓴다 — 어느 쪽이든 저장 로직 자체는 하나뿐이어야 한다.
  Future<void> _saveDraftForNode(AdminStoryNode node) async {
    node.dirty = false;
    await widget.repository.saveNode(widget.packId, node);
    if (!mounted) return;
    // 저장됐으니 이제 Firestore가 최신이다 — 캐시에 남겨 두면 다음에 열 때
    // 방금 저장한 내용을 "아직 저장 안 된 것"처럼 잘못 보여주게 된다.
    widget.sessionCache.remove(widget.packId, node.id);
  }

  /// 승인 요청의 핵심 로직 — [_saveDraftForNode]와 같은 이유로 개별 패널의
  /// "승인 요청 보내기"([_handleRequestApproval])와 그래프 화면의 "전체
  /// 승인 요청 보내기"([_handleBulkRequestApprovalAll])가 공유한다. 확인
  /// 다이얼로그는 호출부 책임이다 — 일괄 처리 쪽은 "N개를 한 번에 보낼까요"
  /// 하나로 묻고, 개별 쪽은 지금처럼 노드 하나 기준 문구로 묻는다.
  Future<void> _requestApprovalForNode(AdminStoryNode node) async {
    final isNew = node.isNew;
    node.pendingAction = isNew ? PendingAction.create : PendingAction.edit;
    node.dirty = false;
    // 이전에 반려됐던 노드를 고쳐서 다시 제출하는 것일 수 있다 — 새로
    // 제출한 버전에 옛 반려 사유가 그대로 남아 있으면 안 되므로 지운다.
    node.rejectionReason = null;
    await widget.repository.saveNode(widget.packId, node);
    await widget.repository.stampApprovalRequestedAt(
      widget.packId,
      node.id,
    ); // ← 추가
    if (!mounted) return;
    widget.sessionCache.remove(widget.packId, node.id);
  }

  /// 방금 저장한 노드가 지금 패널에 열려 있던 바로 그 노드였다면, "새 노드
  /// 만들기로 방금 생성됨" 컨텍스트([_creationSourceId]/
  /// [_creationSourceChoiceIndex])도 같이 정리한다 — 캐시 엔트리가 사라진
  /// 뒤에도 헤더에 "새 노드 (...)"가 계속 남아있으면 안 된다.
  void _clearCreationContextIfSaved(String savedNodeId) {
    if (_editingNode?.id != savedNodeId) return;
    if (widget.sessionCache.has(widget.packId, savedNodeId)) return;
    _creationSourceId = null;
    _creationSourceChoiceIndex = null;
  }

  /// 구조보기에서 선택지로 새 노드를 만들면(_connectToNewNode/
  /// _createNewNodeForChoice, story_map_view.dart) 원본 노드의 choices에도
  /// 새 항목이 추가되지만, 그 변경은 세션 캐시에만 스테이징될 뿐 저장되지
  /// 않는다 — 지금 열려 있는 새 노드 쪽만 명시적으로 저장(임시저장/승인요청)
  /// 되기 때문이다. 그 상태로 세션 캐시가 사라지면(탭 새로고침 등) 원본
  /// 노드가 Firestore에서 이 연결이 생기기 전 상태로 되돌아가 있어서, 방금
  /// 만든 새 노드가 그래프에서 고아가 된다(실제로 겪은 버그).
  ///
  /// 새 노드를 저장/승인요청할 때마다 원본 노드도 같이 저장해서 이 문제를
  /// 막는다 — 단, **항상 임시저장(draft)으로만** 반영한다. 원본 노드를
  /// 승인 대기 상태로 억지로 밀어넣지는 않는다: 원본 노드 자체의 내용을
  /// 검토받을지는 작가가 그 노드를 직접 열어서 판단할 일이지, 다른 노드를
  /// 만들다가 부수효과로 결정될 일이 아니다.
  Future<void> _persistCreationSourceEdgeIfNeeded() async {
    final sourceId = _creationSourceId;
    if (sourceId == null) return;

    final sourceNode = widget.sessionCache.get(widget.packId, sourceId);
    if (sourceNode == null) return; // 이미 저장됐거나 애초에 안 건드렸다.

    await _saveDraftForNode(sourceNode);
  }

  Future<void> _handleSaveDraft() async {
    final node = _editingNode;
    if (node == null) return;

    await _fillCreationChoiceLabelIfNeeded();
    if (!mounted) return;

    await _persistCreationSourceEdgeIfNeeded();
    if (!mounted) return;

    await _saveDraftForNode(node);
    if (!mounted) return;

    _clearCreationContextIfSaved(node.id);
    setState(() {});
    unawaited(_refreshUnsubmittedNodes());

    _showToast(context, '임시저장됨 ✓ (변경사항 전체 승인요청으로 제출하기 전까지는 아무한테도 안 보여요)');
  }

  /// "구조 보기"의 "전체 임시저장" — 지금 이 팩의 세션 캐시에 있는 노드
  /// 전부를 [_saveDraftForNode] 하나로 순서대로 저장한다. 개별 저장과
  /// 똑같이 확인 다이얼로그 없이 바로 진행한다("나만 보임"이라 위험이
  /// 낮다는 게 개별 임시저장 버튼과 같은 판단).
  Future<void> _handleBulkSaveDraftAll() async {
    final ids = widget.sessionCache.nodeIdsForPack(widget.packId).toList();
    if (ids.isEmpty) return;

    final failed = <String>[];
    var succeeded = 0;
    for (final id in ids) {
      final node = widget.sessionCache.get(widget.packId, id);
      if (node == null) continue;
      try {
        await _saveDraftForNode(node);
        if (!mounted) return;
        succeeded += 1;
        _clearCreationContextIfSaved(id);
      } catch (_) {
        failed.add(id);
      }
    }

    if (!mounted) return;
    setState(() {});
    unawaited(_refreshUnsubmittedNodes());

    if (failed.isEmpty) {
      _showToast(context, '$succeeded개 노드를 임시저장했어요 ✓');
    } else {
      _showFailureToast(context, action: '임시저장', failedIds: failed);
    }
  }

  /// "구조 보기"의 "전체 승인 요청 보내기" — 개별 승인 요청과 같은 확인
  /// 다이얼로그를 한 번만 띄운 뒤(노드 수만큼 여러 번 묻지 않는다),
  /// [_requestApprovalForNode]로 전부 처리한다.
  Future<void> _handleBulkRequestApprovalAll() async {
    final ids = widget.sessionCache.nodeIdsForPack(widget.packId).toList();
    if (ids.isEmpty) return;

    final confirmed = await showConfirmDialog(
      context,
      '${ids.length}개 노드의 변경사항을 한 번에 승인 요청 보낼까요? 상위 관리자가 승인해야 플레이어에게 반영돼요.',
    );
    if (!confirmed || !mounted) return;

    final failed = <String>[];
    var succeeded = 0;
    for (final id in ids) {
      final node = widget.sessionCache.get(widget.packId, id);
      if (node == null) continue;
      try {
        await _requestApprovalForNode(node);
        if (!mounted) return;
        succeeded += 1;
        _clearCreationContextIfSaved(id);
      } catch (_) {
        failed.add(id);
      }
    }

    if (!mounted) return;
    setState(() {});
    unawaited(_refreshUnsubmittedNodes());

    if (failed.isEmpty) {
      _showToast(context, '$succeeded개 노드의 승인 요청을 보냈어요 ✓ 상위 관리자 승인 대기 중');
    } else {
      _showFailureToast(context, action: '승인 요청', failedIds: failed);
    }
  }

  /// "노드별로 쓰기" 사이드바의 "변경사항 전체 승인요청" — 노드마다 따로
  /// "승인 요청 보내기"를 누르던 걸 대체한다. [_refreshUnsubmittedNodes]가
  /// 찾아 둔, 이 팩에서 임시저장은 됐지만 아직 승인 대기로 안 넘어간 노드
  /// 전부를 [_requestApprovalForNode](기존 단일 노드 제출 로직)로 순서대로
  /// 제출한다 — 새 제출 경로를 따로 만들지 않는다.
  Future<void> _handleBulkSubmitAllChanges() async {
    final targets = _allUnsubmittedNodes();
    if (targets.isEmpty) return;

    final confirmed = await showConfirmDialog(
      context,
      '${targets.length}개 노드의 변경사항을 한 번에 승인 요청 보낼까요? 상위 관리자가 승인해야 플레이어에게 반영돼요.',
    );
    if (!confirmed || !mounted) return;

    final failed = <String>[];
    var succeeded = 0;
    for (final node in targets) {
      try {
        await _requestApprovalForNode(node);
        if (!mounted) return;
        succeeded += 1;
        _clearCreationContextIfSaved(node.id);
      } catch (_) {
        failed.add(node.id);
      }
    }

    if (!mounted) return;
    setState(() {});
    unawaited(_refreshUnsubmittedNodes());

    if (failed.isEmpty) {
      _showToast(context, '$succeeded개 노드의 승인 요청을 보냈어요 ✓ 상위 관리자 승인 대기 중');
    } else {
      _showFailureToast(context, action: '승인 요청', failedIds: failed);
    }
  }

  /// 세션 캐시에 있는 노드 중 [AdminStoryNode.hasUnsubmittedChanges]가 true인
  /// 것만 — Firestore 조회가 전혀 없는 순수 로컬 계산이라(사이드바 "수정됨"
  /// 배지가 매 build마다 하는 것과 정확히 같은 일) 언제 불러도 항상 그 순간의
  /// 최신 값이다. **버튼을 누르는 시점까지 기다릴 필요가 없다** — 그래서
  /// build()의 "수정됨" 배지 계산(`unsavedNodeIds`)과
  /// [_handleBulkSubmitAllChanges](버튼 클릭 핸들러, build 바깥) 둘 다 이
  /// 메서드를 그대로 부른다.
  ///
  /// ⚠️ 예전엔 이 부분(캐시에 있는 노드)도 [_refreshUnsubmittedNodes]가 채우는
  /// `_unsubmittedNodes`에 같이 담겨서, "노드 편집 중(임시저장 전)"에는 그
  /// 메서드가 다시 불릴 때까지(임시저장/승인요청/일괄 처리/삭제 직후, 최초
  /// 로드) 새로 고른 값이 버튼 개수에 반영되지 않는 지연이 있었다 —
  /// "수정됨" 배지는 매 build마다 다시 계산돼 즉시 보이는데, 버튼 개수만
  /// 뒤처지는 비대칭이었다(BGM을 막 고른 직후 배지는 뜨는데 버튼 개수엔 안
  /// 잡히던 증상이 이거였다 — 특정 필드의 비교 로직 문제가 아니라, 캐시
  /// 기반 판단 자체가 지연 새로고침에 묶여 있던 게 원인). 캐시 조회는
  /// Firestore를 안 타므로 매번 다시 계산해도 비용이 없어서, 아예 지연
  /// 없이 항상 즉시 계산하는 쪽으로 분리했다.
  List<AdminStoryNode> _cachedUnsubmittedNodes() {
    return [
      for (final id in widget.sessionCache.nodeIdsForPack(widget.packId))
        if (widget.sessionCache.get(widget.packId, id)?.hasUnsubmittedChanges ??
            false)
          widget.sessionCache.get(widget.packId, id)!,
    ];
  }

  /// [_cachedUnsubmittedNodes](즉시 계산, 세션 캐시)와
  /// [_persistedUnsubmittedNodes](지연 새로고침, Firestore) 둘을 합친 것 —
  /// "변경사항 전체 승인요청" 버튼의 개수/제출 대상이 실제로 쓰는 목록.
  /// 세션 캐시에 있는 노드는 [_persistedUnsubmittedNodes] 쪽에 우연히 같은
  /// id로 남아 있어도 무시한다 — 캐시 쪽 판단이 항상 더 최신이다(예:
  /// [_refreshUnsubmittedNodes]가 아직 못 따라온 사이 다시 열어서 고친 경우).
  List<AdminStoryNode> _allUnsubmittedNodes() {
    final cached = _cachedUnsubmittedNodes();
    final cacheResidentIds = widget.sessionCache
        .nodeIdsForPack(widget.packId)
        .toSet();
    final persistedOnly = _persistedUnsubmittedNodes.where(
      (n) => !cacheResidentIds.contains(n.id),
    );
    return [...cached, ...persistedOnly];
  }

  /// [_persistedUnsubmittedNodes]를 채운다 — "이 팩에서 Firestore엔 이미
  /// 임시저장돼 있지만(pendingAction == null) 세션 캐시엔 없는" 노드 중
  /// liveSnapshot과 실제로 다른 것들([AdminStoryNode.hasUnsubmittedChanges]).
  /// 요약(AdminStoryNodeSummary)만으로는 이걸 판단할 수 없어서(본문 전체를
  /// 안 갖고 있다) 노드 하나씩 전체를 불러와 비교해야 한다.
  ///
  /// 세션 캐시에 있는 노드는 [_cachedUnsubmittedNodes]가 즉시 계산하므로
  /// (Firestore 조회 없음) 여기서는 다루지 않는다 — 그래서 매 build마다
  /// 다시 계산하지 않아도 된다. Firestore 조회가 섞여 있어서 스트림이
  /// 갱신될 때마다 돌리면 낭비다 — 대신 노드가 실제로 바뀔 만한 시점
  /// (임시저장/승인요청/일괄 처리/삭제 직후, 처음 목록이 도착했을 때)마다
  /// 명시적으로 다시 부른다.
  Future<void> _refreshUnsubmittedNodes() async {
    if (_isRefreshingUnsubmitted) return;
    _isRefreshingUnsubmitted = true;
    try {
      final result = <AdminStoryNode>[];
      final cacheResidentIds = widget.sessionCache
          .nodeIdsForPack(widget.packId)
          .toSet();

      for (final summary in _lastRawSummaries) {
        if (cacheResidentIds.contains(summary.id) ||
            summary.pendingAction != null) {
          continue;
        }
        final node = await widget.repository.fetchNode(
          widget.packId,
          summary.id,
        );
        if (!mounted) return;
        if (node == null) continue;
        if (node.hasUnsubmittedChanges) {
          result.add(node);
        }
      }

      if (!mounted) return;
      setState(() => _persistedUnsubmittedNodes = result);
    } finally {
      _isRefreshingUnsubmitted = false;
    }
  }

  Future<void> _handleCancelDeleteRequest() async {
    final node = _editingNode;
    if (node == null) return;

    node.pendingAction = null;
    await widget.repository.saveNode(widget.packId, node);
    if (!mounted) return;
    setState(() {});
  }

  /// NodeEditor.onChanged — "노드별로 쓰기"의 NodeEditor와 "구조 보기"의
  /// [_NodeEditorPanel]이 둘 다 이 메서드 하나를 그대로 쓴다(같은 편집
  /// 세션을 공유하므로 로직도 하나면 충분하다).
  void _handleEditorChanged(AdminStoryNode editingNode) {
    // 노드 ID 입력칸은 신규 초안일 때만 편집 가능하고, 그 동안 사용자가
    // id를 바꿨을 수 있다 — 그러면 캐시 키도 옮겨야 예전 id로 캐시된
    // 항목이 유령으로 남지 않는다.
    if (_selectedNodeId != null && _selectedNodeId != editingNode.id) {
      widget.sessionCache.remove(widget.packId, _selectedNodeId!);
    }
    if (editingNode.isNew || editingNode.hasUnsubmittedChanges) {
      widget.sessionCache.put(widget.packId, editingNode);
    } else {
      widget.sessionCache.remove(widget.packId, editingNode.id);
    }
    setState(() => _selectedNodeId = editingNode.id);
  }

  /// "구조 보기"의 편집 패널을 닫는다 — 그래프 화면은 그대로 두고 선택만
  /// 해제한다("노드별로 쓰기"로 옮기지 않는다).
  void _handleClosePanel() {
    setState(() {
      _selectedNodeId = null;
      _editingNode = null;
      _creationSourceId = null;
      _creationSourceChoiceIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminStoryNodeSummary>>(
      stream: _nodeSummariesStream,
      builder: (context, snapshot) {
        // Firestore에 실제로 저장된 노드만 담는다 — id 자동 제안
        // (suggestSequentialNodeIds)과 "한 번에 쓰기"의 순서 계산은 반드시
        // 이 목록만 봐야 한다. 아래 displaySummaries(사이드바 표시용, 아직
        // 저장 안 한 초안까지 포함)를 여기 섞어 넘기면, 방금 만든 미저장
        // 초안이 이미 존재하는 노드로 카운트되어 다음 "+" 클릭 때 번호를
        // 하나 건너뛴다(실제로 겪은 버그).
        final rawSummaries = List<AdminStoryNodeSummary>.from(
          snapshot.data ?? const [],
        );
        _lastRawSummaries = rawSummaries;

        if (!_unsubmittedFirstLoadAttempted) {
          _unsubmittedFirstLoadAttempted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_refreshUnsubmittedNodes());
          });
        }

        // 프로토타입(selectedIndex = 0)과 맞춰, 처음 목록이 들어오면 첫 노드를
        // 자동으로 선택한다 — 한 번만 시도해서 사용자가 명시적으로 선택 해제한
        // 뒤(예: 새 노드 삭제) 다시 자동 선택되지 않게 한다.
        if (!_autoSelectAttempted &&
            _selectedNodeId == null &&
            rawSummaries.isNotEmpty) {
          _autoSelectAttempted = true;
          final firstId = rawSummaries.first.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedNodeId == null) _selectNode(firstId);
          });
        }

        final editingNode = _editingNode;

        // "+ 새 스토리 노드"로 만든 뒤 아직 한 번도 저장하지 않은 상태인지 —
        // rawSummaries(Firestore에 실제로 저장된 목록)에 이 id가 없으면
        // 아직 저장 전이라는 뜻이다. 별도 필드로 직접 관리하지 않는 이유:
        // 캐시에서 복원한 신규 초안을 다시 선택할 때 값을 깜빡 false로
        // 고정해 버리는 버그가 있었다(실제로 겪음) — rawSummaries 기준으로
        // 매 build마다 다시 계산하면 그런 수동 동기화 실수 자체가 없어진다.
        final isNewUnsaved =
            editingNode != null &&
            !rawSummaries.any((s) => s.id == editingNode.id);

        // 사이드바 표시 전용 목록. 세션 캐시에 있는 노드는(이미 저장된 적
        // 있는 노드를 손댄 것이든, 한 번도 저장 안 한 신규 초안이든) 항상
        // rawSummaries 대신 캐시 값을 쓴다 — 그래야 순서를 드래그로 바꾸거나
        // 본문을 고친 게 저장 전에도 미리보기(순서, 배경 이미지 인계 계산)에
        // 바로 반영된다. rawSummaries 자체는 절대 건드리지 않는다.
        final displaySummaries = <AdminStoryNodeSummary>[];
        final coveredIds = <String>{};

        for (final raw in rawSummaries) {
          final cached = widget.sessionCache.get(widget.packId, raw.id);
          displaySummaries.add(cached == null ? raw : summaryFromNode(cached));
          coveredIds.add(raw.id);
        }
        for (final cachedId in widget.sessionCache.nodeIdsForPack(
          widget.packId,
        )) {
          if (coveredIds.contains(cachedId)) continue;
          final cached = widget.sessionCache.get(widget.packId, cachedId);
          if (cached == null) continue;
          displaySummaries.add(summaryFromNode(cached));
          coveredIds.add(cachedId);
        }
        displaySummaries.sort((a, b) => a.order.compareTo(b.order));

        // "수정됨" 배지 — [_cachedUnsubmittedNodes]가 즉시 계산하는 값을
        // 그대로 쓴다. "변경사항 전체 승인요청" 버튼의 개수/대상
        // ([_allUnsubmittedNodes])도 캐시에 있는 노드에 대해서는 정확히
        // 같은 메서드를 그대로 재사용한다 — 두 표시가 서로 다른 기준/다른
        // 새로고침 타이밍으로 어긋나지 않도록 "이 노드가 바뀌었는가" 판단은
        // 이 한 곳에서만 한다.
        final unsavedNodeIds = _cachedUnsubmittedNodes()
            .map((n) => n.id)
            .toSet();

        _syncEditingNodeWithLiveSummary(editingNode, rawSummaries);

        // 다른 화면에서 승인/삭제되어 목록에서 사라진 노드는 일괄 삭제 선택에서도
        // 같이 걷어낸다 — 안 그러면 "선택 삭제 (N)" 숫자가 더 이상 존재하지
        // 않는 노드까지 세게 된다.
        _bulkDeleteSelection.removeWhere(
          (id) => !displaySummaries.any((s) => s.id == id),
        );

        final inheritedBackgroundImageId = editingNode == null
            ? null
            : resolveInheritedBackgroundImage(
                nodes: displaySummaries.map(
                  (s) => (
                    order: s.order,
                    backgroundImage: s.backgroundImageId,
                    backgroundAppliesForward: s.backgroundAppliesForward,
                  ),
                ),
                targetOrder: editingNode.order,
                packDefaultBackgroundImage: widget.pack.defaultBackgroundImage,
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ViewModeToggle(
              mode: _viewMode,
              showBulkOption: widget.pack.type == StoryPackType.linear,
              onChanged: (mode) => setState(() => _viewMode = mode),
            ),
            Expanded(
              child: StreamBuilder<List<AdminImage>>(
                stream: _imagesStream,
                builder: (context, imgSnapshot) {
                  final images = imgSnapshot.data ?? const <AdminImage>[];

                  return StreamBuilder<List<AdminSfx>>(
                    stream: _sfxLibraryStream,
                    builder: (context, sfxSnapshot) {
                      final sfxLibrary = sfxSnapshot.data ?? const <AdminSfx>[];

                      return StreamBuilder<List<AdminBgm>>(
                        stream: _bgmLibraryStream,
                        builder: (context, bgmSnapshot) {
                          final bgmLibrary =
                              bgmSnapshot.data ?? const <AdminBgm>[];

                          return StreamBuilder<List<AdminTtsVoice>>(
                            stream: _ttsVoicesStream,
                            builder: (context, ttsVoicesSnapshot) {
                              final ttsVoices =
                                  ttsVoicesSnapshot.data ??
                                  const <AdminTtsVoice>[];

                              return switch (_viewMode) {
                                _ViewMode.bulk => BulkNodeWriter(
                                  onSave: (pages) =>
                                      _handleBulkSave(pages, rawSummaries),
                                ),
                                _ViewMode.map => StoryMapView(
                                  packId: widget.packId,
                                  packType: widget.pack.type,
                                  nodes: displaySummaries,
                                  unsavedNodeIds: unsavedNodeIds,
                                  sessionCache: widget.sessionCache,
                                  repository: widget.repository,
                                  // 더 이상 "노드별로 쓰기"로 넘어가지 않는다 — 그래프
                                  // 화면 안에서 바로 [_NodeEditorPanel]로 연다(같은
                                  // _selectNode가 _editingNode/_creationSourceId를
                                  // 채워 주면, 아래로 내려주는 editingNode 등이 자동으로
                                  // 그 값을 반영한다).
                                  onOpenNode: (id) => _selectNode(id),
                                  onNodeCreatedFromDrag:
                                      (newNodeId, sourceId, choiceIndex) =>
                                          _selectNode(
                                            newNodeId,
                                            creationSourceId: sourceId,
                                            creationSourceChoiceIndex:
                                                choiceIndex,
                                          ),
                                  onChanged: () => setState(() {}),
                                  editingNode: editingNode,
                                  editingNodeDirty:
                                      editingNode != null &&
                                      widget.sessionCache.has(
                                        widget.packId,
                                        editingNode.id,
                                      ),
                                  editingNodeIdEditable: isNewUnsaved,
                                  images: images,
                                  inheritedBackgroundImageId:
                                      inheritedBackgroundImageId,
                                  editingNodeCreationSourceId:
                                      editingNode != null &&
                                          _selectedNodeId == editingNode.id
                                      ? _creationSourceId
                                      : null,
                                  onEditorChanged: () =>
                                      _handleEditorChanged(editingNode!),
                                  onSaveDraft: _handleSaveDraft,
                                  onCancelDeleteRequest:
                                      _handleCancelDeleteRequest,
                                  onClosePanel: _handleClosePanel,
                                  onBulkSaveDraft: _handleBulkSaveDraftAll,
                                  onBulkRequestApproval:
                                      _handleBulkRequestApprovalAll,
                                  sfxLibrary: sfxLibrary,
                                  bgmLibrary: bgmLibrary,
                                  ttsVoices: ttsVoices,
                                  onRefreshTtsVoices: _handleRefreshTtsVoices,
                                  refreshingTtsVoices: _refreshingTtsVoices,
                                  ttsVoiceRepository: widget.ttsVoiceRepository,
                                  defaultTtsVoiceId:
                                      widget.pack.defaultTtsVoiceId,
                                ),
                                _ViewMode.single => Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    StoryNodeSidebar(
                                      nodes: displaySummaries,
                                      selectedNodeId: _selectedNodeId,
                                      unsavedNodeIds: unsavedNodeIds,
                                      onAddNode: () =>
                                          _handleAddNode(rawSummaries),
                                      unsubmittedCount:
                                          _allUnsubmittedNodes().length,
                                      onSubmitAllChanges:
                                          _handleBulkSubmitAllChanges,
                                      onSelect: (id) {
                                        if (id == _selectedNodeId) return;
                                        _selectNode(id);
                                      },
                                      onDelete: (id) =>
                                          _handleDeleteNode(id, rawSummaries),
                                      onReorder: (oldIndex, newIndex) =>
                                          _handleReorder(
                                            displaySummaries,
                                            oldIndex,
                                            newIndex,
                                          ),
                                      bulkSelectedIds: _bulkDeleteSelection,
                                      onToggleBulkSelect:
                                          _toggleBulkDeleteSelect,
                                      onToggleSelectAll: () =>
                                          _toggleBulkDeleteSelectAll(
                                            displaySummaries,
                                          ),
                                      onBulkDelete: _handleBulkDelete,
                                    ),
                                    Expanded(
                                      child: editingNode == null
                                          ? Center(
                                              child: Text(
                                                '노드를 선택하거나 새로 만들어주세요.',
                                                style: TextStyle(
                                                  color: AdminColors.muted,
                                                ),
                                              ),
                                            )
                                          : NodeEditor(
                                              // id 문자열이 아니라 객체 identity로 키를
                                              // 잡는다 — "새 스토리 노드"를 두 번
                                              // 누르면 두 번째도 같은 id를 제안할 수
                                              // 있어서(취소된 적 없는 세션 캐시 기준
                                              // 재확인), _selectedNodeId 문자열만으로는
                                              // 항상 다른 값이라는 보장이 없다.
                                              // ValueKey(id)를 쓰면 Flutter가 "같은
                                              // 위젯"으로 보고 NodeBodyEditor의
                                              // TextFormField를 다시 만들지 않아 화면에
                                              // 이전 내용이 남는다. editingNode는
                                              // 세션이 바뀔 때마다 다른 인스턴스이므로
                                              // ObjectKey는 id 충돌과 무관하게 항상
                                              // 다시 마운트한다.
                                              key: ObjectKey(editingNode),
                                              node: editingNode,
                                              dirty: widget.sessionCache.has(
                                                widget.packId,
                                                editingNode.id,
                                              ),
                                              isIdEditable: isNewUnsaved,
                                              images: images,
                                              sfxLibrary: sfxLibrary,
                                              bgmLibrary: bgmLibrary,
                                              ttsVoices: ttsVoices,
                                              onRefreshTtsVoices:
                                                  _handleRefreshTtsVoices,
                                              refreshingTtsVoices:
                                                  _refreshingTtsVoices,
                                              ttsVoiceRepository:
                                                  widget.ttsVoiceRepository,
                                              packId: widget.packId,
                                              defaultTtsVoiceId:
                                                  widget.pack.defaultTtsVoiceId,
                                              packType: widget.pack.type,
                                              candidates: displaySummaries,
                                              inheritedBackgroundImageId:
                                                  inheritedBackgroundImageId,
                                              creationSourceId:
                                                  _selectedNodeId ==
                                                      editingNode.id
                                                  ? _creationSourceId
                                                  : null,
                                              onChanged: () =>
                                                  _handleEditorChanged(
                                                    editingNode,
                                                  ),
                                              onSaveDraft: _handleSaveDraft,
                                              onCancelDeleteRequest:
                                                  _handleCancelDeleteRequest,
                                            ),
                                    ),
                                  ],
                                ),
                              };
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "노드별로 쓰기"/"한 번에 쓰기"(linear 팩만)/"구조 보기" 3방향 토글.
class _ViewModeToggle extends StatelessWidget {
  final _ViewMode mode;
  final bool showBulkOption;
  final ValueChanged<_ViewMode> onChanged;

  const _ViewModeToggle({
    required this.mode,
    required this.showBulkOption,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AdminColors.panel,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _ModeButton(
            label: '노드별로 쓰기',
            selected: mode == _ViewMode.single,
            onTap: () => onChanged(_ViewMode.single),
          ),
          if (showBulkOption) ...[
            const SizedBox(width: 8),
            _ModeButton(
              label: '한 번에 쓰기',
              selected: mode == _ViewMode.bulk,
              onTap: () => onChanged(_ViewMode.bulk),
            ),
          ],
          const SizedBox(width: 8),
          _ModeButton(
            label: '구조 보기',
            selected: mode == _ViewMode.map,
            onTap: () => onChanged(_ViewMode.map),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AdminColors.gold : AdminColors.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AdminColors.gold : AdminColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

/// "전체 임시저장"/"전체 승인 요청 보내기"가 일부 노드에서 실패했을 때
/// 쓴다 — 실패한 노드 id를 그대로 나열해서, 조용히 몇 개가 빠졌는지 모르고
/// 넘어가는 일이 없게 한다. 성공한 나머지는 이미 세션 캐시에서 지워졌으니
/// (실패한 것만 계속 "수정됨"으로 남는다), 실패 목록 자체가 "이 노드들만
/// 다시 시도하면 된다"는 안내이기도 하다.
void _showFailureToast(
  BuildContext context, {
  required String action,
  required List<String> failedIds,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '$action 중 일부 실패: ${failedIds.join(', ')}',
        style: TextStyle(color: AdminColors.rejectText),
      ),
      backgroundColor: AdminColors.rejectBg,
      duration: const Duration(seconds: 6),
    ),
  );
}

void _showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: AdminColors.panel2,
      duration: const Duration(seconds: 2),
    ),
  );
}
