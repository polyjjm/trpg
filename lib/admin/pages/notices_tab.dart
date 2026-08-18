import 'package:flutter/material.dart';

import '../data/admin_notice_repository.dart';
import '../models/writer_notice.dart';
import '../widgets/admin_theme.dart';
import '../widgets/labeled_field.dart';

/// "공지사항" 탭 — 지금 선택된 스토리팩 기준으로 작가 공지를 올리고 목록을 본다.
/// 게임 앱의 라이브러리/상세 화면(lib/features/catalog)에서 packId로 걸러 보여준다.
class NoticesTab extends StatefulWidget {
  final String packId;
  final AdminNoticeRepository repository;

  const NoticesTab({super.key, required this.packId, required this.repository});

  @override
  State<NoticesTab> createState() => _NoticesTabState();
}

class _NoticesTabState extends State<NoticesTab> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _handlePost() async {
    if (_titleController.text.trim().isEmpty) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AdminColors.panel,
          content: Text(
            '제목을 입력해주세요.',
            style: TextStyle(color: AdminColors.ivory),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                '확인',
                style: TextStyle(color: AdminColors.gold),
              ),
            ),
          ],
        ),
      );
      return;
    }

    await widget.repository.createNotice(
      packId: widget.packId,
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
    );

    _titleController.clear();
    _bodyController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '작가 공지사항',
              style: TextStyle(
                fontSize: 16,
                color: AdminColors.ivory,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "내 스토리팩 업데이트/새 이야기 출시 같은 소식을 올리면, 플레이어가 라이브러리에서 볼 수 있어요.",
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '제목',
              child: TextField(
                controller: _titleController,
                style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                decoration: adminInputDecoration(
                  hintText: "제목 (예: 새로운 확장 이야기 '추적자' 공개!)",
                ),
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '내용',
              child: TextField(
                controller: _bodyController,
                maxLines: 4,
                minLines: 3,
                style: TextStyle(color: AdminColors.ivory, fontSize: 13),
                decoration: adminInputDecoration(hintText: '내용을 적어주세요.'),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _handlePost,
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '공지 올리기',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 24),
            StreamBuilder<List<WriterNotice>>(
              stream: widget.repository.watchNoticesForPack(widget.packId),
              builder: (context, snapshot) {
                final notices = snapshot.data ?? const <WriterNotice>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '등록된 공지 ${notices.length}개',
                      style: TextStyle(fontSize: 13, color: AdminColors.muted),
                    ),
                    const SizedBox(height: 10),
                    for (final notice in notices)
                      _NoticeCard(
                        notice: notice,
                        onDelete: () =>
                            widget.repository.deleteNotice(notice.id),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final WriterNotice notice;
  final VoidCallback onDelete;

  const _NoticeCard({required this.notice, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notice.date,
            style: TextStyle(fontSize: 11, color: AdminColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            notice.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AdminColors.ivory,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            notice.body,
            style: TextStyle(
              fontSize: 13,
              color: AdminColors.ivory,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onDelete,
            child: const Text(
              '삭제',
              style: TextStyle(fontSize: 12, color: AdminColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
