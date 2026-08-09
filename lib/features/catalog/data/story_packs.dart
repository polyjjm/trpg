import '../../../core/constants/asset_paths.dart';
import '../models/story_pack.dart';

/// 현재 유일한 이야기 팩(ZOMBIE ROAD)의 id.
/// 상세 화면에서 이 팩일 때만 기존 스토리 진입점으로 연결한다.
const String zombieRoadPackId = 'zombie_road';

/// QA용 유료 테스트 팩의 id.
const String qaPaidTestPackId = 'qa_paid_test';

/// 하드코딩된 이야기 팩 목록. 아직 Firestore 등 원격 콘텐츠 DB에서 불러오지 않으며,
/// 이는 이후 데이터 마이그레이션 단계에서 대체될 예정이다.
final List<StoryPack> storyPacks = [
  const StoryPack(
    id: zombieRoadPackId,
    title: 'ZOMBIE ROAD',
    description:
        '무너진 거리에서 내일을 고를 수 있을까.\n선택은 기록이 되고, 기록은 생존이 된다.\n'
        '탐색, 전투, 아이템, 확률 이벤트가 이어지는 스토리 선택형 생존 게임.',
    authorName: '제작자',
    coverImage: UiPaths.mainBg,
    price: 0,
    format: StoryPackFormat.trpg,
  ),

  // QA 전용 placeholder. 유료 팩의 무료 미리보기·페이월 흐름을 테스트하기 위해
  // ZOMBIE ROAD 스토리 콘텐츠를 그대로 재사용한다. 다른 작가의 실제 유료 콘텐츠가
  // 생기면 이 항목은 지운다.
  const StoryPack(
    id: qaPaidTestPackId,
    title: '테스트 유료 스토리',
    description: '페이월 흐름 QA용 placeholder. ZOMBIE ROAD 콘텐츠를 그대로 재사용한다.',
    authorName: 'QA',
    coverImage: UiPaths.mainBg,
    price: 3000,
    format: StoryPackFormat.trpg,
    previewNodeLimit: 2,
  ),
];
