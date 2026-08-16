import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/user/author_application_status.dart';
import '../data/author_application_repository.dart';
import '../models/author_application.dart';
import '../widgets/admin_theme.dart';
import '../widgets/info_banner.dart';
import '../widgets/labeled_field.dart';

/// 작가 신청 폼. 최초 신청(신청서 없음)과 반려 후 재신청([previousApplication]의
/// status가 rejected) 둘 다 이 화면 하나로 처리한다 — 입력 항목은 같고, 반려
/// 사유 배너 유무와 필드 초기값만 다르다.
///
/// 자기소개(bio)를 화면에서 가장 크고 눈에 띄는 입력칸으로 두고, 링크 추가
/// 버튼은 마지막 링크 칸에 내용이 들어가야만 나타난다 — 쓰지 않을 기능은
/// 화면에서 조용히 있어야 한다는 원칙(doc/planning-doc_multi-author-story-platform.md
/// §7)을 이 폼에도 그대로 적용한 것.
class AuthorApplicationPage extends StatefulWidget {
  final User user;
  final AuthorApplication? previousApplication;
  final AuthorApplicationRepository repository;
  final VoidCallback onSubmitted;
  final VoidCallback onSignOut;

  const AuthorApplicationPage({
    super.key,
    required this.user,
    required this.previousApplication,
    required this.repository,
    required this.onSubmitted,
    required this.onSignOut,
  });

  @override
  State<AuthorApplicationPage> createState() => _AuthorApplicationPageState();
}

class _AuthorApplicationPageState extends State<AuthorApplicationPage> {
  late final TextEditingController _displayNameController = TextEditingController(
    text: widget.previousApplication?.displayName ?? widget.user.displayName ?? '',
  );
  late final TextEditingController _bioController = TextEditingController(
    text: widget.previousApplication?.bio ?? '',
  );
  late final List<TextEditingController> _linkControllers = [
    for (final link in widget.previousApplication?.portfolioLinks ?? const <String>[])
      TextEditingController(text: link),
    TextEditingController(),
  ];

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_onFieldChanged);
    _bioController.addListener(_onFieldChanged);
    for (final controller in _linkControllers) {
      controller.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() => setState(() {});

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    for (final controller in _linkControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit =>
      !_isSubmitting &&
      _displayNameController.text.trim().isNotEmpty &&
      _bioController.text.trim().isNotEmpty;

  void _addLinkField() {
    setState(() {
      _linkControllers.add(TextEditingController()..addListener(_onFieldChanged));
    });
  }

  void _removeLinkField(int index) {
    setState(() {
      _linkControllers.removeAt(index).dispose();
    });
  }

  Future<void> _handleSubmit() async {
    setState(() => _isSubmitting = true);

    final links =
        _linkControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();

    await widget.repository.submitApplication(
      uid: widget.user.uid,
      displayName: _displayNameController.text.trim(),
      bio: _bioController.text.trim(),
      portfolioLinks: links,
    );

    if (!mounted) return;
    widget.onSubmitted();
  }

  @override
  Widget build(BuildContext context) {
    final rejectionReason = widget.previousApplication?.rejectionReason;
    final showRejection = widget.previousApplication?.status == AuthorApplicationStatus.rejected &&
        rejectionReason != null &&
        rejectionReason.isNotEmpty;

    return Scaffold(
      backgroundColor: AdminColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '작가로 신청하기',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AdminColors.ivory),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '간단한 소개만 있으면 충분해요. 승인되면 이 계정으로 바로 이야기를 쓸 수 있어요.',
                    style: TextStyle(fontSize: 13, color: AdminColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  if (showRejection) ...[
                    InfoBanner(
                      text: '이전 신청이 반려됐어요: $rejectionReason\n내용을 보완해서 다시 제출해주세요.',
                      style: InfoBannerStyle.dirty,
                    ),
                    const SizedBox(height: 20),
                  ],
                  LabeledField(
                    label: '이름/필명',
                    child: TextField(
                      controller: _displayNameController,
                      style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
                      decoration: adminInputDecoration(hintText: '독자에게 보일 이름'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  LabeledField(
                    label: '자기소개',
                    child: TextField(
                      controller: _bioController,
                      minLines: 6,
                      maxLines: 10,
                      style: const TextStyle(color: AdminColors.ivory, fontSize: 14, height: 1.6),
                      decoration: adminInputDecoration(hintText: '어떤 이야기를 쓰고 싶으신가요? 자유롭게 적어주세요.'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  LabeledField(
                    label: '기존 작품 링크 (선택)',
                    child: Column(
                      children: [
                        for (var i = 0; i < _linkControllers.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _linkControllers[i],
                                    style: const TextStyle(color: AdminColors.ivory, fontSize: 13),
                                    decoration: adminInputDecoration(hintText: 'https://...'),
                                  ),
                                ),
                                if (_linkControllers.length > 1) ...[
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _removeLinkField(i),
                                    child: const Icon(Icons.close_rounded, size: 18, color: AdminColors.muted),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        if (_linkControllers.last.text.trim().isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              onTap: _addLinkField,
                              child: const Text('+ 링크 추가', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canSubmit ? _handleSubmit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.gold,
                        disabledBackgroundColor: AdminColors.panel2,
                        foregroundColor: Colors.black,
                        disabledForegroundColor: AdminColors.muted,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        _isSubmitting ? '제출 중...' : '신청서 제출하기',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: InkWell(
                      onTap: widget.onSignOut,
                      child: const Text('로그아웃', style: TextStyle(fontSize: 12, color: AdminColors.muted)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
