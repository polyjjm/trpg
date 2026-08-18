import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:sotry_trpg/core/auth/google_auth_service.dart';
import 'package:sotry_trpg/core/platform/remove_app_loading.dart';
import 'package:sotry_trpg/firebase_options.dart';

import 'migration/node_block_migration.dart';
import 'migration/node_shape_audit.dart';

/// 노드 blocks 구조 마이그레이션 dry-run + 스키마 감사 도구. 게임 앱
/// (lib/main.dart)/작가 편집기(lib/main_admin.dart)와는 별개인 세 번째 Flutter
/// 엔트리 포인트로, `flutter run -d chrome -t tool/migrate_node_blocks_dry_run.dart`로만
/// 실행한다 — main.dart/main_admin.dart는 이 파일을 전혀 참조하지 않는다.
///
/// 두 가지 읽기 전용 리포트를 제공한다(**Firestore에는 아무것도 쓰지 않는다**):
/// - dry-run: 옛 평평한 구조(body 있고 blocks 없음) 노드가 새 blocks 구조로
///   바뀔 모습을 미리 보여준다.
/// - 구조 감사: storyPacks/*/nodes 전체를 스캔해 옛 평평한 세대/옛 선택지
///   트리거(AdminChoice) 세대/새 blocks 세대가 각각 몇 건인지, 그리고 지금
///   NodeEditor로 열면 내용이 조용히 사라질 위험이 있는 문서가 몇 건인지 센다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const _DryRunApp());
}

class _DryRunApp extends StatelessWidget {
  const _DryRunApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '노드 blocks 마이그레이션 (dry-run)',
      theme: ThemeData.dark(),
      home: const _DryRunPage(),
    );
  }
}

class _DryRunPage extends StatefulWidget {
  const _DryRunPage();

  @override
  State<_DryRunPage> createState() => _DryRunPageState();
}

class _DryRunPageState extends State<_DryRunPage> {
  final _authService = GoogleAuthService();
  final _firestore = FirebaseFirestore.instance;

  bool _running = false;
  String _status = '이 Firebase 프로젝트에 접근 권한이 있는 계정으로 로그인한 뒤 실행할 리포트를 눌러주세요.';
  List<NodeMigrationPreview> _previews = const [];
  List<NodeShapeAudit> _riskyAudits = const [];

  @override
  void initState() {
    super.initState();
    // web/index.html의 #app-loading 스플래시는 Flutter 로더 콜백이 아니라
    // 순수 DOM 조작으로 지운다(MainPage/AdminGatePage와 같은 패턴) — 이 진입점도
    // 첫 프레임이 그려진 뒤(initState) 직접 지워줘야 스플래시 뒤에 화면이 계속 숨어있지 않는다.
    removeAppLoadingSplash();
  }

  Future<void> _signIn() async {
    final result = await _authService.signIn();
    setState(() {
      _status = result.success ? '로그인됨 — dry-run을 실행할 수 있어요.' : (result.errorMessage ?? '로그인 실패');
    });
  }

  Future<void> _runDryRun() async {
    if (!_authService.isSignedIn) {
      setState(() => _status = '먼저 로그인해주세요.');
      return;
    }

    setState(() {
      _running = true;
      _status = '노드를 읽는 중...';
      _previews = const [];
    });

    // collectionGroup 읽기 전용 조회라 별도 색인이 필요 없다
    // (FIRESTORE_SCHEMA.md의 "복합 색인이 필요한 쿼리" 참고 — where 없는
    // 단순 조회는 해당 없음).
    final snapshot = await _firestore.collectionGroup('nodes').get();
    final previews = <NodeMigrationPreview>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (!isOldFlatShapeNode(data)) continue;
      final packId = doc.reference.parent.parent!.id;
      previews.add(NodeMigrationPreview.fromOldNode(packId, doc.id, data));
    }

    _printReport(previews, totalScanned: snapshot.docs.length);

    if (!mounted) return;
    setState(() {
      _running = false;
      _previews = previews;
      _status = '완료 — 총 ${snapshot.docs.length}개 노드 중 ${previews.length}개가 옛 구조예요. '
          '콘솔에 상세 리포트를 출력했어요. Firestore에는 아무것도 쓰지 않았어요.';
    });
  }

  void _printReport(List<NodeMigrationPreview> previews, {required int totalScanned}) {
    debugPrint('===== 노드 blocks 마이그레이션 dry-run 리포트 =====');
    debugPrint('스캔한 노드 총 $totalScanned개, 옛 구조 ${previews.length}개, 쓰기 없음(dry-run).');

    for (final preview in previews) {
      debugPrint('--------------------------------------------------');
      debugPrint('pack: ${preview.packId} / node: ${preview.nodeId}');
      debugPrint('[old] body:');
      debugPrint(preview.oldBody);
      debugPrint('[old] bgImageId: ${preview.oldBgImageId}');
      debugPrint('[new] proposed blocks (${preview.proposedBlocks.length}개):');
      for (var i = 0; i < preview.proposedBlocks.length; i++) {
        debugPrint('  [$i] ${preview.proposedBlocks[i]}');
      }
      debugPrint('[new] proposed backgroundImage: ${preview.proposedBackgroundImage}');
    }

    debugPrint('===== 리포트 끝 =====');
  }

  Future<void> _runShapeAudit() async {
    if (!_authService.isSignedIn) {
      setState(() => _status = '먼저 로그인해주세요.');
      return;
    }

    setState(() {
      _running = true;
      _status = '노드를 읽는 중...';
      _riskyAudits = const [];
    });

    final snapshot = await _firestore.collectionGroup('nodes').get();
    final audits = snapshot.docs.map((doc) {
      final packId = doc.reference.parent.parent!.id;
      return NodeShapeAudit.fromFirestore(packId, doc.id, doc.data());
    }).toList();

    _printShapeAuditReport(audits);

    if (!mounted) return;
    final risky = audits.where((a) => a.atRiskOfSilentDataLoss).toList();
    setState(() {
      _running = false;
      _riskyAudits = risky;
      _status = '구조 감사 완료 — 총 ${audits.length}개 노드 스캔. 콘솔에 상세 리포트를 출력했어요. '
          'Firestore에는 아무것도 쓰지 않았어요.';
    });
  }

  void _printShapeAuditReport(List<NodeShapeAudit> audits) {
    final flatBody = audits.where((a) => a.hasFlatBody).toList();
    final legacyTitleOrDay = audits.where((a) => a.hasLegacyTitleOrDay).toList();
    final legacyChoices = audits.where((a) => a.hasLegacyChoiceTriggers).toList();
    final newBlocks = audits.where((a) => a.hasBlocks).toList();
    final newChoices = audits.where((a) => a.hasNewStyleChoices).toList();
    final risky = audits.where((a) => a.atRiskOfSilentDataLoss).toList();

    debugPrint('===== 노드 스키마 감사 리포트 =====');
    debugPrint('스캔한 노드 총 ${audits.length}개, 쓰기 없음.');
    debugPrint('- 옛 평평한 구조(body 필드 있음): ${flatBody.length}개');
    debugPrint('- 옛 평평한 구조(day/title 필드 있음): ${legacyTitleOrDay.length}개');
    debugPrint('- 옛 선택지 트리거 구조(AdminChoice 모양 — move/battle/encounter/merchant/item): '
        '${legacyChoices.length}개');
    debugPrint('- 새 blocks 구조: ${newBlocks.length}개');
    debugPrint('- 새 choices 구조(label/nextNodeId만): ${newChoices.length}개');
    debugPrint('- 지금 NodeEditor로 열면 내용이 조용히 사라질 위험이 있는 문서: ${risky.length}개');

    if (risky.isNotEmpty) {
      debugPrint('--------------------------------------------------');
      debugPrint('위험 문서 목록 (pack / node / 사유):');
      for (final a in risky) {
        final reasons = <String>[
          if (a.hasFlatBody && !a.hasBlocks) 'body만 있고 blocks 없음(본문이 빈 문단 1개로 보임)',
          if (a.hasLegacyChoiceTriggers) '옛 선택지 트리거(전투/조우/상인/아이템 분기)가 label/nextNodeId로 안 읽힘',
        ];
        debugPrint('  ${a.packId} / ${a.nodeId}: ${reasons.join(', ')}');
      }
    }

    debugPrint('===== 리포트 끝 =====');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('노드 blocks 마이그레이션 / 스키마 감사')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton(onPressed: _signIn, child: const Text('Google 로그인')),
                ElevatedButton(
                  onPressed: _running ? null : _runDryRun,
                  child: Text(_running ? '실행 중...' : 'blocks 변환 dry-run'),
                ),
                ElevatedButton(
                  onPressed: _running ? null : _runShapeAudit,
                  child: Text(_running ? '실행 중...' : '스키마 감사(옛 선택지 트리거 등)'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('전체 리포트(원문 포함)는 콘솔(디버그 출력)에서 확인하세요. 아래는 화면용 요약이에요.'),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (_previews.isNotEmpty) ...[
                    const Text('blocks 변환 dry-run 결과', style: TextStyle(fontWeight: FontWeight.bold)),
                    for (final preview in _previews)
                      ListTile(
                        title: Text('${preview.packId} / ${preview.nodeId}'),
                        subtitle: Text(
                          '문단 ${preview.proposedBlocks.length}개'
                          '${preview.proposedBackgroundImage != null ? ' · 배경 ${preview.proposedBackgroundImage}' : ''}',
                        ),
                      ),
                    const Divider(height: 24),
                  ],
                  if (_riskyAudits.isNotEmpty) ...[
                    const Text(
                      '지금 NodeEditor로 열면 내용이 사라질 위험이 있는 문서',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final audit in _riskyAudits)
                      ListTile(
                        title: Text('${audit.packId} / ${audit.nodeId}'),
                        subtitle: Text([
                          if (audit.hasFlatBody && !audit.hasBlocks) 'body만 있고 blocks 없음',
                          if (audit.hasLegacyChoiceTriggers) '옛 선택지 트리거(전투/조우/상인/아이템)',
                        ].join(' · ')),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
