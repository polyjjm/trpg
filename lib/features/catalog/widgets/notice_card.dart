import 'package:flutter/material.dart';

import '../models/notice.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);

/// 공지사항 가로 스크롤 카드. 탭하면 전체 본문을 보여주는 다이얼로그를 띄운다.
class NoticeCard extends StatelessWidget {
  final Notice notice;

  const NoticeCard({super.key, required this.notice});

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
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showDetail(context),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _gold.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_rounded, color: _gold, size: 15),
                const SizedBox(width: 6),
                Text(
                  notice.date,
                  style: TextStyle(fontSize: 11, color: _ivory.withOpacity(0.55)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              notice.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: _ivory,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
