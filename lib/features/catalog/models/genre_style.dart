import 'package:flutter/material.dart';

/// 장르 slug → 표시용 스타일(라벨/색/아이콘). 관리자 쪽 genres 컬렉션과 같은
/// slug 어휘를 쓴다 — 리더 앱이 지금은 Firestore genres를 읽지 않아 하드코딩
/// 되어 있지만, 나중에 실제 데이터로 옮겨갈 때 슬러그가 그대로 맞도록 미리
/// 맞춰 둔 것이다.
class GenreStyle {
  final String label;
  final Color color;
  final IconData icon;

  const GenreStyle({required this.label, required this.color, required this.icon});
}

const Map<String, GenreStyle> _genreStyles = {
  'horror': GenreStyle(label: '공포', color: Color(0xFFB33A3A), icon: Icons.nights_stay_rounded),
  'romance': GenreStyle(label: '로맨스', color: Color(0xFFE0648C), icon: Icons.favorite_rounded),
  'scifi': GenreStyle(label: 'SF', color: Color(0xFF3A8FB3), icon: Icons.rocket_launch_rounded),
  'fantasy': GenreStyle(label: '판타지', color: Color(0xFF7A5CC7), icon: Icons.auto_awesome_rounded),
  'thriller': GenreStyle(label: '스릴러', color: Color(0xFFB3672E), icon: Icons.bolt_rounded),
  'slice_of_life': GenreStyle(label: '일상물', color: Color(0xFFB3A23A), icon: Icons.wb_sunny_rounded),
};

const GenreStyle _defaultGenreStyle = GenreStyle(label: '기타', color: Color(0xFF8A8690), icon: Icons.menu_book_rounded);

/// 모르는/아직 없는 슬러그는 조용히 기본 스타일로 떨어진다 — 화면이 깨지는 것보다
/// "장르 미상"처럼 보이는 편이 낫다.
GenreStyle genreStyleFor(String genreSlug) => _genreStyles[genreSlug] ?? _defaultGenreStyle;
