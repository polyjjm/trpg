import '../models/notice.dart';

/// 하드코딩된 공지사항 목록. 아직 백엔드에서 불러오지 않는다.
final List<Notice> notices = [
  const Notice(
    title: 'ZOMBIE ROAD 라이브러리 오픈',
    date: '2026.08.09',
    body:
        '라이브러리에서 이야기를 골라 시작할 수 있도록 개편되었습니다.\n'
        '앞으로 더 많은 이야기 팩이 이 서가에 추가될 예정이니 기대해 주세요.',
  ),
  const Notice(
    title: '클라우드 저장 안내',
    date: '2026.08.09',
    body:
        '진행 상황은 로그인한 계정에 자동으로 저장됩니다.\n'
        '다른 기기에서 로그인해도 이어서 플레이할 수 있습니다.',
  ),
];
