import 'package:flutter/material.dart';

import '../data/notices.dart';
import '../models/notice.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 하단 탭의 "공지사항" — 예전 홈 화면의 가로 스크롤 카드 대신, 전체 공지를
/// 세로로 훑어볼 수 있는 단순한 목록이다. 탭하면 전체 본문을 보여준다.
class NoticeListTab extends StatelessWidget {
  const NoticeListTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '공지사항',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ivory),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: notices.isEmpty
                    ? Center(
                        child: Text(
                          '등록된 공지사항이 없습니다',
                          style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.55)),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 20),
                        itemCount: notices.length,
                        separatorBuilder: (_, _) => Divider(color: Colors.white.withOpacity(0.08), height: 1),
                        itemBuilder: (context, index) => _NoticeListRow(notice: notices[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeListRow extends StatelessWidget {
  final Notice notice;

  const _NoticeListRow({required this.notice});

  void _showDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: Text(notice.title, style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                notice.date,
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              ),
              const SizedBox(height: 12),
              Text(
                notice.body,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.campaign_rounded, color: _gold, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ivory),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notice.date,
                    style: TextStyle(fontSize: 11.5, color: _ivory.withOpacity(0.50)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _ivory.withOpacity(0.35), size: 20),
          ],
        ),
      ),
    );
  }
}
