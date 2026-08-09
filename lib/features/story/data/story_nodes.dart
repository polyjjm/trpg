import '../models/story_choice.dart';
import '../models/story_node.dart';

const String storyStartNodeId = 'intro_01';

final Map<String, StoryNode> storyNodes = {
  'intro_01': StoryNode(
    id: 'intro_01',
    dayLabel: 'DAY 1',
    title: '폐허가 된 도시 외곽',
    text:
        '도시는 이미 무너져 있었다.\n하지만 아직 끝난 것은 아니었다.\n살아남기 위해, 나는 걸음을 옮겼다.',
    choices: [
      StoryChoice(
        text: '무너진 편의점으로 들어간다.',
        nextNodeId: 'convenience_store_01',
      ),
      StoryChoice(
        text: '소리가 들린 골목으로 향한다.',
        encounterTrigger: const StoryEncounterTrigger(
          encounterId: 'zombie_01',
          winNodeId: 'alley_after_win',
          escapeNodeId: 'alley_after_escape',
        ),
      ),
      StoryChoice(
        text: '인기척이 느껴지는 주유소 쪽으로 다가간다.',
        encounterTrigger: const StoryEncounterTrigger(
          encounterId: 'raider_01',
          winNodeId: 'raider_after_win',
          escapeNodeId: 'raider_after_escape',
        ),
      ),
      StoryChoice(
        text: '낡은 수레를 끌고 다니는 사람을 발견한다.',
        merchantTrigger: const StoryMerchantTrigger(
          nextNodeId: 'after_merchant_01',
        ),
      ),
    ],
  ),

  'convenience_store_01': StoryNode(
    id: 'convenience_store_01',
    dayLabel: 'DAY 1',
    title: '무너진 편의점',
    text: '선반은 대부분 비어 있었다.\n하지만 구석에서 통조림 몇 개가 눈에 띄었다.',
    choices: [
      StoryChoice(
        text: '통조림을 챙기고 다시 골목으로 향한다.',
        encounterTrigger: const StoryEncounterTrigger(
          encounterId: 'zombie_01',
          winNodeId: 'alley_after_win',
          escapeNodeId: 'alley_after_escape',
        ),
      ),
      StoryChoice(
        text: '조용히 밖으로 되돌아간다.',
        nextNodeId: 'intro_01',
      ),
    ],
  ),

  'alley_after_win': StoryNode(
    id: 'alley_after_win',
    dayLabel: 'DAY 1',
    title: '골목, 그 이후',
    text:
        '좀비는 쓰러졌다.\n숨을 고르며, 다음 갈 곳을 생각한다.\n(이어지는 이야기는 다음 업데이트에서 계속됩니다.)',
    choices: [],
  ),

  'alley_after_escape': StoryNode(
    id: 'alley_after_escape',
    dayLabel: 'DAY 1',
    title: '골목에서 도망치다',
    text: '뒤를 돌아보지 않고 달렸다.\n숨이 턱까지 차오를 때쯤에야 멈춰 섰다.',
    choices: [
      StoryChoice(
        text: '편의점 쪽으로 몸을 숨긴다.',
        nextNodeId: 'convenience_store_01',
      ),
    ],
  ),

  'raider_after_win': StoryNode(
    id: 'raider_after_win',
    dayLabel: 'DAY 1',
    title: '주유소, 그 이후',
    text:
        '약탈자들은 더 이상 움직이지 않았다.\n좀비만이 아니라 사람도 위협이 되는 세상이었다.\n(이어지는 이야기는 다음 업데이트에서 계속됩니다.)',
    choices: [],
  ),

  'raider_after_escape': StoryNode(
    id: 'raider_after_escape',
    dayLabel: 'DAY 1',
    title: '주유소에서 물러나다',
    text: '약탈자들의 발소리가 멀어질 때까지, 나는 몸을 숨긴 채 움직이지 않았다.',
    choices: [
      StoryChoice(
        text: '다시 큰길 쪽으로 되돌아간다.',
        nextNodeId: 'intro_01',
      ),
    ],
  ),

  'after_merchant_01': StoryNode(
    id: 'after_merchant_01',
    dayLabel: 'DAY 1',
    title: '상인과 헤어지다',
    text: '"또 보세, 살아있으면 말이지."\n상인은 수레를 끌고 다시 폐허 속으로 사라졌다.',
    choices: [
      StoryChoice(
        text: '다시 큰길 쪽으로 돌아간다.',
        nextNodeId: 'intro_01',
      ),
    ],
  ),

  'game_over': StoryNode(
    id: 'game_over',
    dayLabel: 'DAY 1',
    title: '생존 실패',
    text: '의식이 흐려진다.\n여기까지였다.',
    choices: [],
  ),
};
