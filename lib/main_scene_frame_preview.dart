import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/platform/remove_app_loading.dart';
import 'core/state/game_state_provider.dart';
import 'firebase_options.dart';
import 'reader/shared/models/node_block.dart';
import 'reader/shared/models/node_block_type.dart';
import 'reader/shared/scene_frame.dart';

/// SceneFrame(lib/reader/shared/scene_frame.dart) 단독 미리보기 진입점 —
/// 인터랙티브/선형 리더(Task 2)가 실제로 붙기 전, 배경 배너/블록 타이핑/설정
/// 시트 동작을 눈으로 확인하기 위한 임시 진입점이다. lib/main_admin.dart와
/// 같은 이유로 별도 진입점을 뒀다 — 게임 앱 라우팅을 건드리지 않고 이 화면만
/// 띄워볼 수 있다.
///
///   flutter run -d chrome -t lib/main_scene_frame_preview.dart
///
/// 리더가 실제 Firestore 노드로 SceneFrame을 구동하게 되면 이 파일은 지워도 된다.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const _ScenePreviewApp());
}

class _ScenePreviewApp extends StatelessWidget {
  const _ScenePreviewApp();

  @override
  Widget build(BuildContext context) {
    return GameStateProvider(
      child: MaterialApp(
        title: 'SceneFrame 미리보기',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          fontFamily: 'NotoSansKR',
        ),
        home: const _ScenePreviewPage(),
      ),
    );
  }
}

const List<NodeBlock> _sampleBlocks = [
  NodeBlock(
    type: NodeBlockType.paragraph,
    text: '문을 열자 차가운 바람이 얼굴을 스쳤다. 복도 끝에서 희미한 불빛이 흔들리고 있었다.',
  ),
  NodeBlock(
    type: NodeBlockType.beat,
    text: '— 그때, 등 뒤에서 발소리가 들렸다.',
  ),
  NodeBlock(
    type: NodeBlockType.paragraph,
    text: '돌아볼 용기가 나지 않았지만, 여기서 멈춰 있을 수도 없었다. 한 걸음, 또 한 걸음.',
    ttsOverride: '돌아볼 용기가 나지 않았지만 여기서 멈춰 있을 수도 없었다.',
  ),
];

class _ScenePreviewPage extends StatefulWidget {
  const _ScenePreviewPage();

  @override
  State<_ScenePreviewPage> createState() => _ScenePreviewPageState();
}

class _ScenePreviewPageState extends State<_ScenePreviewPage> {
  @override
  void initState() {
    super.initState();
    // web/index.html의 #app-loading 스플래시는 Flutter 로더 콜백이 아니라 순수
    // DOM 조작으로 지운다(MainPage/AdminGatePage와 같은 패턴) — 이 진입점도 첫
    // 프레임이 그려진 뒤(initState) 직접 지워줘야 스플래시 뒤에 화면이 계속
    // 숨어있지 않는다.
    removeAppLoadingSplash();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SceneFrame(
        key: const ValueKey('preview-node-1'),
        blocks: _sampleBlocks,
        backgroundImageUrl: null,
        ttsAllowed: true,
        actionAreaBuilder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewChoiceButton(label: '조용히 다가간다', onTap: () => _showSnack(context, '조용히 다가간다')),
            const SizedBox(height: 10),
            _PreviewChoiceButton(label: '큰 소리로 외친다', onTap: () => _showSnack(context, '큰 소리로 외친다')),
          ],
        ),
      ),
    );
  }

  void _showSnack(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('선택: $label')));
  }
}

class _PreviewChoiceButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PreviewChoiceButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFF6B4A), Color(0xFFFFB648)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}
