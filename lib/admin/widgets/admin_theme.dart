import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 작가 도구 전용 라이트/다크 모드 상태 — 앱 전체 ThemeMode(lib/main.dart)와는
/// 별개로, 이 도구(lib/main_admin.dart)에만 적용된다.
///
/// [AdminColors]의 기본 팔레트(bg/panel/panel2/border/ivory/muted)가 이 값을
/// 보고 라이트/다크를 고르는 getter다 — [toggle]이 [mode]를 바꾸면 그 즉시
/// 모든 getter 호출이 새 값을 반환하고, 상위 위젯이 다시 그려지면서 화면
/// 전체에 반영된다.
class AdminTheme {
  AdminTheme._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

  static const _prefsKey = 'admin_theme_mode';

  /// 앱 시작 시 한 번 저장된 선택을 불러온다. 저장된 값이 없으면 다크(기본값)
  /// 그대로 둔다.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == 'light') mode.value = ThemeMode.light;
    } catch (_) {
      // 저장소 접근이 막힌 환경(예: 일부 브라우저의 프라이빗 모드)이어도
      // 다크 기본값으로 계속 동작해야 한다 — 조용히 무시한다.
    }
  }

  static Future<void> toggle() async {
    mode.value = mode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        mode.value == ThemeMode.light ? 'light' : 'dark',
      );
    } catch (_) {
      // 이번 세션 안에서는 여전히 토글이 동작하니, 저장만 실패해도 무시한다.
    }
  }

  static bool get isDark => mode.value == ThemeMode.dark;
}

/// admin_design_mockup.html(디자인 목업, 코랄 액센트 + 웜톤 다크 팔레트)의
/// 색상 변수를 옮긴 팔레트. lib/admin/ 안에서만 쓰는 공용 상수라, 파일마다
/// private 색상 상수를 반복하는 게임 쪽 관례 대신 한 곳에 모아 둔다.
///
/// 기본 팔레트 6개(bg/panel/panel2/border/ivory/muted)는 [AdminTheme.mode]에
/// 따라 값이 바뀌는 getter다 — `static const`가 아니라서 이 파일을 쓰는
/// 쪽에서 `const TextStyle(color: AdminColors.ivory)`처럼 `const` 컨텍스트
/// 안에 직접 넣을 수 없다(컴파일 타임 상수가 아니므로). 그 자리들은 전부
/// `const`를 떼어내는 기계적인 수정이 필요했다 — 실제 로직은 그대로다.
/// 나머지 필드(gold/danger/status* 등)는 라이트/다크에서 같은 값을 쓰는
/// 게 의도적이라(예: 상태 배지는 항상 옅은 파스텔 톤) `static const`로 남겨
/// 뒀다 — 여기까지 getter로 바꾸면 손댈 자리만 늘어나고 얻는 게 없다.
class AdminColors {
  AdminColors._();

  static bool get _isDark => AdminTheme.isDark;

  static Color get bg =>
      _isDark ? const Color(0xFF17140F) : const Color(0xFFFBF8F3);
  static Color get panel =>
      _isDark ? const Color(0xFF221D16) : const Color(0xFFFFFFFF);
  static Color get panel2 =>
      _isDark ? const Color(0xFF1E1A14) : const Color(0xFFF2EDE4);
  static Color get border =>
      _isDark ? const Color(0xFF3A352C) : const Color(0xFFE2DBCC);
  static Color get ivory =>
      _isDark ? const Color(0xFFE8E5DF) : const Color(0xFF2C271F);
  static Color get muted =>
      _isDark ? const Color(0xFFA8A296) : const Color(0xFF83795F);

  /// 유저 이메일/닉네임 같은 작은 배지의 배경 — panel/panel2보다 한 단계
  /// 더 도드라져야 해서 별도 값을 둔다.
  static Color get badgeBg =>
      _isDark ? const Color(0xFF3A3A2A) : const Color(0xFFEFE8D8);

  static Color get inputFill => panel2;
  static Color get inputBorder => _isDark ? border : const Color(0xFFDCD3C0);
  static Color get inputDisabledBorder => inputBorder.withOpacity(0.5);
  static Color get inputText => ivory;
  static Color get inputDropdownMenuBg => panel2;

  /// 체크 안 된 상태의 박스 — 체크되면 어느 모드든 코랄(gold)로 채워지고
  /// 흰 체크 아이콘을 쓴다(다른 선택 상태 표시와 같은 액센트를 재사용하는
  /// 것). 대비가 필요한 건 "체크 안 된 빈 박스가 배경에 묻히지 않는지"라서,
  /// 그 상태만 라이트/다크에 따라 다르게 그린다.
  static Color get checkboxUncheckedFill =>
      _isDark ? const Color(0xFF17140F) : Colors.white;
  static Color get checkboxUncheckedBorder =>
      _isDark ? const Color(0xFF5A5348) : const Color(0xFFB8AE99);
  static const Color checkboxCheckColor = Colors.white;

  /// 코랄 — 목업의 유일한 강조색(탭 밑줄, 선택된 노드 행 테두리, 주요 액션
  /// 버튼 등). 이름은 예전 골드 팔레트 시절 그대로 남겨 뒀다 — 코드 전체에서
  /// "강조색" 자리로 이미 이 이름을 쓰고 있어서, 값만 바꾸는 쪽이 이름을
  /// 전부 바꾸는 것보다 훨씬 적은 변경으로 코랄을 전체에 반영할 수 있었다.
  static const gold = Color(0xFFD85A30);

  /// "+ 새 스토리 노드"처럼 코랄을 꽉 채우지 않고 옅게만 쓰는 자리(목업의
  /// 소프트 칩 버튼) 전용.
  static const coralSoftBg = Color(0xFFFAECE7);
  static const coralSoftText = Color(0xFF712B13);

  static const danger = Color(0xFFE0524B);
  static const accent = Color(0xFF4B8EE0);
  static const ok = Color(0xFF6FBF73);

  static const statusDraftBg = Color(0xFF3A3A2A);
  static const statusDraftText = Color(0xFFD8C98A);

  // 연재중 — 사용자가 지정한 정확한 값.
  static const statusPublishedBg = Color(0xFFEAF3DE);
  static const statusPublishedText = Color(0xFF27500A);

  // 검토중(등록/수정 승인대기) — 사용자가 지정한 정확한 값.
  static const statusPendingBg = Color(0xFFFAEEDA);
  static const statusPendingText = Color(0xFF633806);

  static const statusPendingDeleteBg = Color(0xFF422A2A);
  static const statusPendingDeleteText = Color(0xFFFF9D9D);

  static const dirtyBannerBg = Color(0xFF3D2F1A);
  static const dirtyBannerBorder = Color(0xFF6B5324);
  static const dirtyBannerText = Color(0xFFE8C877);

  static const liveNoteBg = Color(0xFF1A2D3D);
  static const liveNoteBorder = Color(0xFF244A63);
  static const liveNoteText = Color(0xFF8FC7E8);

  static const approveBg = Color(0xFFEAF3DE);
  static const approveText = Color(0xFF27500A);
  static const approveBorder = Color(0xFF2C5C34);
  static const rejectBg = Color(0xFF3D1F1F);
  static const rejectText = Color(0xFFFF9D9D);
  static const rejectBorder = Color(0xFF5C2C2C);
}
