import 'package:flutter/material.dart';

import '../data/notice_repository.dart';
import '../models/notice.dart';
import '../widgets/home_desktop_layout.dart';

const Color _ivory = Color(0xFFE2D4BF);
const Color _gold = Color(0xFFF0E68C);
const Color _coral = Color(0xFFE2703A);

/// 하단 탭(데스크톱에서는 상단 내비)의 "공지사항" — notices 컬렉션
/// (active == true, 최신순)을 구독한다.
///
/// "안 읽음" 갱신(lastNoticeReadAt)은 이 위젯이 아니라 CatalogShellPage가
/// 한다: 이 탭은 IndexedStack 안에 항상 마운트돼 있어서 initState 시점이
/// "탭을 실제로 열었을 때"와 안 맞는다 — 인덱스가 바뀌는 순간을 아는 쪽은
/// CatalogShellPage뿐이다.
///
/// 좁은 폭: 세로 목록 + 탭하면 본문 다이얼로그(기존 그대로).
/// 데스크톱 폭([homeDesktopBreakpoint] 이상): 왼쪽 380px 목록 + 오른쪽 본문
/// 2단. 1440px 화면에서 본문을 작은 AlertDialog로 띄우면 화면 가운데
/// 320px짜리 카드만 뜨고 나머지가 전부 검게 남는다 — 넓은 화면에서는 목록과
/// 본문을 같이 두는 편이 맞다.
class NoticeListTab extends StatefulWidget {
  const NoticeListTab({super.key});

  @override
  State<NoticeListTab> createState() => _NoticeListTabState();
}

class _NoticeListTabState extends State<NoticeListTab> {
  final NoticeRepository _repository = NoticeRepository();
  late final Stream<List<Notice>> _noticesStream = _repository.watchActiveNotices();

  /// 데스크톱 2단에서 오른쪽에 펼쳐 둔 공지의 id. null이면 목록의 첫 번째를
  /// 고른다 — id로 들고 있어야 스트림이 갱신돼 목록 순서가 바뀌어도 선택이
  /// 엉뚱한 공지로 옮겨가지 않는다(인덱스로 들고 있으면 그렇게 된다).
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= homeDesktopBreakpoint;

    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(isDesktop ? 40 : 22, isDesktop ? 28 : 20, isDesktop ? 40 : 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '공지사항',
                style: TextStyle(
                  fontSize: isDesktop ? 22 : 19,
                  fontWeight: FontWeight.w800,
                  color: _ivory,
                ),
              ),
              SizedBox(height: isDesktop ? 22 : 18),
              Expanded(
                child: StreamBuilder<List<Notice>>(
                  stream: _noticesStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      // 조용히 삼키지 않는다 — 규칙/색인 미배포 같은 실제
                      // 실패가 "공지 없음"과 구분 안 되게 두면 안 된다.
                      debugPrint('공지사항 목록 불러오기 실패: ${snapshot.error}');
                      return _CenteredNotice(text: '공지사항을 불러오지 못했어요');
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: _gold));
                    }

                    final notices = snapshot.data ?? const <Notice>[];
                    if (notices.isEmpty) {
                      return _CenteredNotice(text: '등록된 공지사항이 없습니다');
                    }

                    if (!isDesktop) return _MobileList(notices: notices);

                    final selected = notices.firstWhere(
                      (n) => n.id == _selectedId,
                      orElse: () => notices.first,
                    );
                    return _DesktopSplit(
                      notices: notices,
                      selected: selected,
                      onSelect: (notice) => setState(() => _selectedId = notice.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredNotice extends StatelessWidget {
  final String text;

  const _CenteredNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: TextStyle(fontSize: 13, color: _ivory.withOpacity(0.55))),
    );
  }
}

/// 좁은 폭 — 기존 목록 그대로, 탭하면 본문 다이얼로그.
class _MobileList extends StatelessWidget {
  final List<Notice> notices;

  const _MobileList({required this.notices});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: notices.length,
      separatorBuilder: (_, _) => Divider(color: Colors.white.withOpacity(0.08), height: 1),
      itemBuilder: (context, index) => _NoticeListRow(
        notice: notices[index],
        onTap: () => _showDetailDialog(context, notices[index]),
      ),
    );
  }
}

void _showDetailDialog(BuildContext context, Notice notice) {
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
              formatNoticeDate(notice.createdAt),
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            const SizedBox(height: 12),
            Text(notice.body, style: const TextStyle(color: Colors.white70, height: 1.5)),
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

/// 데스크톱 — 왼쪽 380px 목록 + 오른쪽 본문. 다이얼로그를 쓰지 않으므로
/// '닫기' 버튼도 없다(목록에서 다른 공지를 누르면 오른쪽만 바뀐다).
class _DesktopSplit extends StatelessWidget {
  final List<Notice> notices;
  final Notice selected;
  final ValueChanged<Notice> onSelect;

  static const double listWidth = 380;

  const _DesktopSplit({
    required this.notices,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: listWidth,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: notices.length,
                itemBuilder: (context, index) {
                  final notice = notices[index];
                  return _NoticeListRow(
                    notice: notice,
                    selected: notice.id == selected.id,
                    onTap: () => onSelect(notice),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 32),
          Expanded(child: _NoticeBody(notice: selected)),
        ],
      ),
    );
  }
}

class _NoticeBody extends StatelessWidget {
  final Notice notice;

  const _NoticeBody({required this.notice});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(36, 34, 36, 34),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.campaign_rounded, color: _gold, size: 17),
                SizedBox(width: 8),
                Text(
                  '공지',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: _gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              notice.title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _ivory,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              formatNoticeDate(notice.createdAt),
              style: TextStyle(fontSize: 12.5, color: _ivory.withOpacity(0.5)),
            ),
            const SizedBox(height: 24),
            Container(height: 1, color: Colors.white.withOpacity(0.08)),
            const SizedBox(height: 24),
            // 본문 한 줄이 900px까지 늘어나면 눈이 줄을 놓친다 — 읽기 폭을
            // 720으로 잠그고 남는 공간은 여백으로 둔다.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Text(
                notice.body,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.9,
                  color: Colors.white.withOpacity(0.86),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeListRow extends StatelessWidget {
  final Notice notice;
  final bool selected;
  final VoidCallback onTap;

  const _NoticeListRow({
    required this.notice,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withOpacity(0.06) : Colors.transparent,
          border: Border(
            left: BorderSide(color: selected ? _coral : Colors.transparent, width: 2),
            bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.campaign_rounded, color: _gold, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? _ivory : _ivory.withOpacity(0.82),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatNoticeDate(notice.createdAt),
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

String formatNoticeDate(DateTime? date) {
  if (date == null) return '';
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}
