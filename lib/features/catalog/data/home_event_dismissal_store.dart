import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// "이 기기에서 이 이벤트를 오늘 이미 봤는지 / 다시 안 보기로 했는지" —
/// 최근 검색어(home_tab.dart의 _recentSearchesPrefsKey)와 같은 패턴으로,
/// 계정에 동기화하지 않고 기기에만 SharedPreferences로 저장한다. 이 팝업을
/// 봤는지는 기기별로 달라도 되는 정보라 Firestore에 굳이 계정 문서를 만들
/// 필요가 없다.
///
/// eventId별로 독립된 상태를 갖는다 — {"다시 보지 않기"}는 반드시 그 특정
/// eventId에만 적용돼야 한다(전역으로 걸면 admin이 새 이벤트를 만들어도
/// 영영 안 보이게 된다).
class HomeEventDismissalStore {
  static const _prefsKey = 'home_event_dismissals';

  /// [eventId]가 지금 이 기기에서 보여줘도 되는 상태인지 — "다시 보지
  /// 않기"를 누른 적 없고, 오늘(KST) 아직 안 보여줬으면 true.
  Future<bool> shouldShow(String eventId) async {
    final state = await _readState();
    final entry = state[eventId];
    if (entry == null) return true;

    if (entry['neverShowAgain'] == true) return false;
    return entry['lastShownDate'] != _todayKstKey();
  }

  /// 이벤트를 보여준 시점에 호출 — X로 닫든 이미지를 탭해서 이동하든,
  /// "보여줬다"는 사실 자체는 똑같이 기록해서 오늘 안에는 다시 안 뜨게 한다.
  Future<void> markShownToday(String eventId) async {
    await _mutate(eventId, (entry) => entry..['lastShownDate'] = _todayKstKey());
  }

  /// "다시 보지 않기" — 이 eventId에 한해서만 영구적으로 끈다. 새 이벤트가
  /// 생기면 그 이벤트는 다른 eventId라 이 값과 무관하게 정상적으로 뜬다.
  Future<void> markNeverShowAgain(String eventId) async {
    await _mutate(eventId, (entry) => entry..['neverShowAgain'] = true);
  }

  Future<void> _mutate(
    String eventId,
    Map<String, dynamic> Function(Map<String, dynamic> entry) update,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final state = await _readState(prefs: prefs);
      final entry = Map<String, dynamic>.of(
        state[eventId] as Map<String, dynamic>? ?? <String, dynamic>{},
      );
      state[eventId] = update(entry);
      await prefs.setString(_prefsKey, jsonEncode(state));
    } catch (_) {
      // 저장소 접근이 막힌 환경이어도(예: 프라이빗 모드) 이번 세션의 팝업
      // 동작 자체는 계속돼야 한다 — 다음에 또 뜨는 정도의 대가만 남는다.
    }
  }

  Future<Map<String, dynamic>> _readState({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
      return decoded;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 기기 로컬 시간대에 기대지 않고 KST(UTC+9)로 명시적으로 계산한다 —
  /// ranking_repository.dart의 _dateKey와 같은 규칙("YYYY-MM-DD").
  String _todayKstKey() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
