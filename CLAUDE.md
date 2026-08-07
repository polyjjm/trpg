# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A Flutter app (package name `sotry_trpg`) for "ZOMBIE ROAD" — a Korean-language, choice-driven survival story game with turn-based battles. All in-app text and code comments are Korean; keep new UI copy and comments consistent with that.

**Target: mobile release (Android/iOS) is the goal.** `lib/main.dart` used to unconditionally import `dart:html` (to remove the `#app-loading` splash element once Flutter boots), which is web-only in Dart and blocked android/ios compilation. This is now resolved: the splash-removal logic lives behind a conditional export in `lib/core/platform/remove_app_loading.dart` (`remove_app_loading_web.dart` when `dart.library.html` is available, `remove_app_loading_stub.dart` no-op otherwise), so `main.dart` no longer references `dart:html` directly and the codebase can build for both web and mobile.

## Commands

```bash
flutter pub get              # install dependencies
flutter run -d chrome        # run the app (web is the only working target — see above)
flutter analyze              # static analysis (uses flutter_lints via analysis_options.yaml)
flutter test                 # run tests
flutter test test/widget_test.dart   # run a single test file
flutter build web            # production web build
flutter run -d android        # (목표) 모바일 빌드 - 현재는 dart:html 문제로 실패
flutter build apk             # (목표) Android 빌드
flutter build ios             # (목표) iOS 빌드 (macOS 필요)
```

Note: `test/widget_test.dart` is still the default Flutter counter-app template and does not match the current `MyApp`/`MainPage` UI — it will fail if run as-is. There is no other test coverage yet.

## Architecture

Feature-first layout under `lib/features/<feature>/{pages,widgets,models,services,data}`. `lib/pages/`, `lib/models/`, and `lib/app/routes/` exist but are currently empty — they are not the convention in use; put new code under `lib/features/<feature>/...` instead.

### Navigation flow

`main.dart` (`MyApp` → `MainPage`, the title screen) → `StoryPage` (`features/story`) → `BattlePage` (`features/battle`), pushed/popped via `Navigator.push`/`pop` with typed result objects rather than a router package (no named routes, no `go_router`/`Navigator 2.0`).

### Battle system (`lib/features/battle`)

- **Data-driven encounters**: `data/battle_configs.dart` defines a `Map<String, BattleConfig>` keyed by battle id (e.g. `'zombie_01'`), each with enemy stats as random ranges (`BattleStatRange`), messages, weighted drop table (`BattleDropItem`), and escape chance. Callers look up a config by id and pass it into `BattlePage` — add new encounters by adding entries to this map, not by subclassing.
- **`BattlePage`** is a single large `StatefulWidget` that owns the full turn loop (player attack-card selection → resolve damage → enemy attack → win/lose/escape) using `setState` + `Future.delayed` for pacing/animation beats. There's no separate state-management layer (no Provider/Bloc/Riverpod) — battle state lives directly in the widget's State.
- **Attack resolution is card-based**: `BattleService.getBattleCards()` returns a shuffled hand of `BattleCard`s (`fail`/`lightAttack`/`attack`/`heavyAttack`); the player picks one and damage is resolved by card type in `_resolveAttackCard`.
- Battle outcome is communicated back to the caller via `Navigator.pop(context, BattleResult(...))` with `BattleOutcome.win|lose|escape`, remaining HP, and `BattleReward` (dropped item ids) — the caller (`StoryPage`) reads this to branch on the result.
- `features/battle/inventory/` holds `ItemModel`/`ItemEffectType` — item definitions are currently nested inside the battle feature rather than a top-level inventory feature.

### Story system (`lib/features/story`)

`StoryPage` renders background art, a `TypewriterText` animated-reveal widget for narrative copy, and choice buttons that appear once typing completes (`onComplete` callback). Choices can trigger navigation into a battle (see above) or be no-ops for content not yet written.

### Panel system (`lib/features/panel`)

`GameBottomPanel` is a bottom-sheet-style widget with an internal `PanelMenuType` enum (`menu`/`status`/`equipment`/`inventory`) driving which sub-view is shown; opened via `PanelHandleButton`. Status/equipment/inventory views currently render static placeholder text, not live player state.

### Assets

`core/constants/asset_paths.dart` barrel-exports `background_paths.dart`, `character_paths.dart`, and `ui_paths.dart`, each holding `static const` asset path strings — prefer referencing these constants over hardcoding `assets/images/...` literals when touching existing code (though some literals, e.g. in `main.dart`, predate this convention). New image assets must also be declared under `flutter.assets` in `pubspec.yaml` (paths are per-directory, not a blanket `assets/` include) and fonts under `flutter.fonts`.

## Mobile readiness checklist
- [x] Isolate the `dart:html` dependency to web-only (guard with `kIsWeb` or split into platform-specific files)
- [ ] Verify screen size / touch UI (battle card selection, panel system, and other touch interactions)
- [ ] Confirm asset paths and fonts load correctly on mobile
- [ ] In-app purchase / ad SDK integration planned (service not yet decided)
