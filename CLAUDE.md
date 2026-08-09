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
# Game Systems Design

## Core loop
Story-driven survival — branching narrative choices, combat, and random encounter events woven together.

## Random events / mini-games
Chance-based encounters that can trigger during story progression:

- **Merchant/beggar encounters**: while traveling or in town, a random-chance encounter with a merchant or street vendor
    - Bartering (item ↔ item)
    - Buy/sell (currency ↔ item, if a currency system exists)
- **Gambling elements**: encounter triggers a mini-game where the player wagers items/currency
    - Coin flip (heads/tails)
    - (expandable later: dice, card draw, etc.)
- **Random risk encounters**: chance-based threatening NPC/monster encounter that forces a choice (flee / fight / negotiate)

## Shop system
- Fixed shop access at specific story nodes (e.g. a town/village)
- Buy/sell inventory items

## Boss battles
- A distinct, tougher battle placed at the end of certain chapters, separate from regular encounters
- Higher stats than regular monsters + needs unique attack patterns/presentation

## Undecided (to discuss later)
- Whether a currency system exists, or if it's barter-only
- Whether bosses appear once per chapter, or only at specific story points
- Additional gambling/mini-game types
  markdown
## Death / Revival system
- On death, the player is NOT sent back to the very beginning — progress continues from where they died (or a recent checkpoint)
- Revival options on death:
    - **Paid item**: use a premium currency/item to revive on the spot
    - **Watch ad**: watch a rewarded ad to revive (free alternative to paid item)

## Monetization
- **Revival item**: purchasable premium item used to revive after death (see above)
- **Rewarded ads**: ad-based free revival option
- **Expansion packs**: purchasable content packs that unlock additional story chapters/content
- (To decide later: what exactly is gated behind expansion packs — new chapters only, or also exclusive items/monsters?)
  아, CLAUDE.md에 새로 추가할 섹션 내용만 드릴게요. 지금 작업하실 시스템들(스탯/레벨, 아이템, 다수몬스터, 상인, 확장성 시딩)을 Claude Code가 세션 넘어가도 계속 참고할 수 있게, CLAUDE.md 맨 아래에 아래 블록을 그대로 추가하시면 돼요.

markdown
## Planned expansion (in progress)

The following systems are being added on top of the existing architecture. Keep these
consistent as you implement each one — later prompts assume earlier ones are done.

### Player stats / leveling
- `GameState` gains `level`, `exp`, `playerDefense`, plus a `schemaVersion` field in
  `toJson()` for future save-data migration.
- `expToNextLevel()` / `addExp()` handle level-up (possibly multiple levels per call), growing
  `playerMaxHp`/`playerAttack`/`playerDefense` and fully healing on level-up.
- `BattleReward.exp` must actually be populated (currently always 0) and applied via
  `GameState.applyBattleResult()`.

### Combat uses real stats, not hardcoded numbers
- Card damage in `BattlePage._resolveAttackCard()` derives from `player.attack` (multiplier
  per card type), not fixed 15/20/25.
- Incoming damage (`enemyAttack()`, `onDefendPressed()`) is reduced by `playerDefense`.
- Balance (enemy hp/attack ranges, escape/drop chances, fail-card odds) is tuned as one system
  once stats are wired in — don't hardcode numbers without checking they still make sense
  together.

### Item catalog + in-battle item use
- `lib/features/battle/inventory/data/item_catalog.dart`: `Map<String, ItemModel>` — the
  single source of truth for item name/effect/value, keyed by the same ids already used in
  `battle_configs.dart` drop tables (`bandage_01`, `food_01`, `knife_01`, ...).
- `GameBottomPanel`'s inventory view and `BattlePage`'s item-use action must both read from
  this catalog + `GameState.inventory`, not hardcoded placeholder data.
- Used items are tracked in `BattleResult.usedItemIds` (currently always empty).

### Multiple enemies per battle
- `BattleConfig` supports a list of enemy spawns (not just one enemy), and `BattlePage` holds
  `List<BattleUnit> enemies` with simple tap-to-target selection. Single-enemy encounters
  (e.g. `zombie_01`) auto-target since there's only one choice.
- Human (non-zombie) enemies — e.g. `약탈자` raiders — are added as regular `BattleConfig`
  entries using this same multi-enemy structure, not a separate code path.

### Merchant feature (new)
- New `lib/features/merchant/` feature (same shape as `battle`/`story`): barter (item ↔ item
  via a predefined exchange table) and a coin-flip wager minigame (win = double the wagered
  item, lose = item is gone).
- Triggered from story nodes the same way `StoryBattleTrigger` triggers battles — add an
  analogous trigger type on `StoryChoice` rather than a one-off mechanism.

### Auth + cloud save (Firebase)
- `lib/core/auth/auth_service.dart`'s `AuthService` interface now has a real implementation:
  `GoogleAuthService` (`lib/core/auth/google_auth_service.dart`), backed by `firebase_auth` +
  `GoogleAuthProvider` — web popup flow (`signInWithPopup`) via `kIsWeb`, `google_sign_in`
  package flow otherwise. `LocalAuthService` remains as the always-signed-out fallback but
  isn't wired into the app anymore.
- `GameStateProvider` (`lib/core/state/game_state_provider.dart`) owns the `GoogleAuthService`
  and a `CloudSyncController` (`lib/core/state/cloud_sync_controller.dart`), and exposes both
  through `AuthScope` (`lib/core/auth/auth_scope.dart`). `CloudSyncController` listens to
  `GameState` changes and, whenever a user is signed in, saves `GameState.toJson()` to
  Firestore at `users/{uid}/save/current` via `CloudSaveService`
  (`lib/core/state/cloud_save_service.dart`); on sign-in it loads that doc back into the
  existing `GameState` instance via `GameState.loadFromJson()` (creating the doc from current
  state if none exists yet). Signed-out/guest play keeps working purely in memory — nothing is
  synced until `authService.userId` is non-null.
- `MainPage`'s '이어하기' button (`lib/main.dart`) is wired to this: already-signed-in users
  load their cloud save and go straight into `StoryPage`; signed-out users go to
  `SignInPage` (`lib/features/auth/pages/sign_in_page.dart`), which offers "Google로 로그인"
  or "로그인 없이 계속하기" (guest).

### Extensibility seams (not real implementations yet)
- `lib/core/monetization/`: `MonetizationService` interface + no-op default
  (`showRewardedAd()`, `purchaseRevivalItem()` stubs), per the Death/Revival and Monetization
  sections above. Not a real IAP/ad SDK integration yet.
- Keep all story/battle/item content id-driven (already the case) and all asset paths routed
  through `core/constants/*_paths.dart`, so a future remote content DB / asset pipeline can
  slot in without restructuring.

## Mobile readiness checklist (updated)
- [x] Isolate the `dart:html` dependency to web-only
- [ ] Verify screen size / touch UI (battle card selection, panel system, item-use UI, merchant
  UI, and multi-enemy targeting)
- [ ] Confirm asset paths and fonts load correctly on mobile
- [ ] In-app purchase / ad SDK integration planned (service not yet decided — `MonetizationService`
  seam exists but no real SDK chosen)
