# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A Flutter app (package name `sotry_trpg`) for a multi-author interactive/linear story platform — Korean-language, choice-driven stories. All in-app text and code comments are Korean; keep new UI copy and comments consistent with that.

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

`main.dart` (`MyApp` → `MainPage`, the title screen) → `CatalogShellPage` (`features/catalog`, the library/home tab bar) → `StoryPackDetailPage` → `InteractiveReader`/`LinearReader` (`lib/reader/`, picked by `storyPack.format` — see "Reader system" below), all pushed/popped via `Navigator.push`/`pop` with typed result objects rather than a router package (no named routes, no `go_router`/`Navigator 2.0`).

The old hardcoded `features/story/widgets/story_page.dart` (`StoryPage`) has been retired — it rendered the hand-written `features/story/data/story_nodes.dart` content directly. `features/story/data/story_nodes.dart`, `storyStartNodeId`, and the battle/encounter/merchant demo pages it drove are still referenced elsewhere (`GameStateProvider`'s initial `GameState`, `EncounterPage`) and haven't been removed, but nothing routes into that hardcoded story graph as a full reading experience anymore.

### Reader system (`lib/reader/`)

Real per-pack content now flows from Firestore (`storyPacks/{packId}/nodes`, reading each node's `liveSnapshot` — the last-approved content, never the top-level "currently editing" fields, same pattern as `StoryPackRepository`'s `liveMetadata`) via `StoryReaderRepository` (`lib/reader/shared/data/story_reader_repository.dart`), which also resolves each node's background image through the inheritance chain (`lib/core/story/background_image_inheritance.dart`: explicit node value → nearest earlier node by `order` → `storyPack.defaultBackgroundImage` → none) and joins `images/{imageId}` docs to real URLs.

`SceneFrame` (`lib/reader/shared/scene_frame.dart`) is the shared full-screen node renderer both reader types build on: it types out `blocks` (paragraph/beat/image) in order, fades in a background banner, and — once typing completes — fades in a type-specific action area supplied by the caller via `actionAreaBuilder`. It also owns a collapsible bottom settings sheet (TTS play/pause via `lib/reader/shared/tts_controller.dart` wrapping `flutter_tts`, BGM mute via `AudioService`, font selector, typing-animation toggle) backed by a per-user `users/{uid}/readerPrefs/settings` Firestore doc (`ReaderPrefsRepository`).

- `InteractiveReader` (`lib/reader/interactive/`): `storyPack.type == 'interactive'`. Renders `node.choices` as buttons; tapping one calls `GameState.goToNode(choice.nextNodeId)` and swaps to that node in place (no new route per node).
- `LinearReader` (`lib/reader/linear/`): `storyPack.type == 'linear'`. Renders a single "다음" button following `node.nextNodeId`, or "완료" when it's null.
- Both reuse `GameState.ownsPack`/`visitedNodeCount`/`previewNodeLimit` for the free-preview paywall (`lib/reader/shared/paywall.dart`) — note this progress tracking is still global on `GameState`, not per-pack (a pre-existing limitation, unchanged by the reader work).

### Panel system (`lib/features/panel`)

`GameBottomPanel` is a bottom-sheet-style widget with an internal `PanelMenuType` enum (`menu`/`status`/`equipment`/`inventory`) driving which sub-view is shown; opened via `PanelHandleButton`. Status/equipment/inventory views currently render static placeholder text, not live player state.

### Assets

`core/constants/asset_paths.dart` barrel-exports `background_paths.dart`, `character_paths.dart`, and `ui_paths.dart`, each holding `static const` asset path strings — prefer referencing these constants over hardcoding `assets/images/...` literals when touching existing code (though some literals, e.g. in `main.dart`, predate this convention). New image assets must also be declared under `flutter.assets` in `pubspec.yaml` (paths are per-directory, not a blanket `assets/` include) and fonts under `flutter.fonts`.

## Mobile readiness checklist
- [x] Isolate the `dart:html` dependency to web-only (guard with `kIsWeb` or split into platform-specific files)
- [ ] Verify screen size / touch UI (panel system and other touch interactions)
- [ ] Confirm asset paths and fonts load correctly on mobile
- [ ] In-app purchase / ad SDK integration planned (service not yet decided)
## Planned expansion (in progress)

The following systems are being added on top of the existing architecture. Keep these
consistent as you implement each one — later prompts assume earlier ones are done.

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
  load their cloud save and go straight into `CatalogShellPage`; signed-out users go to
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
- [ ] Verify screen size / touch UI (panel system and other touch interactions)
- [ ] Confirm asset paths and fonts load correctly on mobile
- [ ] In-app purchase / ad SDK integration planned (service not yet decided — `MonetizationService`
  seam exists but no real SDK chosen)

## Writer/admin web tool (`lib/admin/`, `lib/main_admin.dart`)

A second, separate Flutter entry point for a writer/admin content editor — not part of the
game app. Same codebase and Firebase project, but a fully separate dependency graph:

```bash
flutter run -d chrome -t lib/main_admin.dart    # run the admin tool
flutter build web -t lib/main_admin.dart        # build only the admin tool
```

`lib/main.dart`/`lib/features/**` never import anything under `lib/admin/`, so
`flutter build apk -t lib/main.dart` (the game's mobile build) never pulls in admin code —
verify this holds with `grep -rl "admin/" lib --include="*.dart" | grep -v ^lib/admin | grep -v main_admin.dart`
(should be empty) whenever touching either side.

- Structure mirrors `lib/features/<feature>/{pages,widgets,models,data}`, just rooted at
  `lib/admin/` instead of `lib/features/admin/` to keep it visually distinct from the game's
  own features.
- Auth reuses `GoogleAuthService` (`lib/core/auth/google_auth_service.dart`) directly — no
  separate auth system. Access is gated by `users/{uid}.role` (`'reader' | 'author' | 'admin'`,
  `lib/core/user/`), not a hardcoded email list — the old
  `lib/admin/data/admin_allowlist.dart` allowlist has been removed. `'author'` and `'admin'`
  both unlock the editor; only `'admin'` gets approval authority (author-application review,
  once built, plus the existing node-approval tab). How an account gets promoted to
  `'author'` in the first place (the application/review flow) is being built incrementally —
  see the "Planned expansion" section below. `AdminGatePage` re-evaluates auth state
  imperatively after sign-in/out (same pattern as the game's `MainPage`/`SignInPage` — no
  reactive auth stream).
- Firestore schema (`storyPacks`, `storyPacks/{packId}/nodes`, `images`, `writerNotices`,
  `users`, `authorApplications`, `genres`) is documented in `lib/admin/FIRESTORE_SCHEMA.md`,
  including the draft → pending-approval → live workflow (`status`/`pendingAction`/
  `liveSnapshot` fields) and a role-based security-rules snippet (`users/{uid}.role`, not a
  hardcoded email) covering every collection above plus a matching Storage-rules snippet for
  `admin/story_images/**`. **Neither has actually been deployed — no `firestore.rules` or
  `storage.rules` file exists in this repo, and nothing has been pushed via the Firebase
  console or `firebase deploy` yet.** Until one of those happens, Firestore itself still lets
  any authenticated user read/write these collections directly via the SDK, regardless of what
  the documented rules say — the client-side role checks are the only thing currently gating
  access.
- The game itself does not read these collections yet — `lib/features/story/data/story_nodes.dart`
  is still the hardcoded source of truth for gameplay. Wiring the game to read published
  content from `storyPacks` is a future data-migration step, same as the catalog's hardcoded
  `storyPacks` list in `lib/features/catalog/data/story_packs.dart` (unrelated Dart model of
  the same name — don't confuse `lib/admin/models/admin_story_pack.dart` with
  `lib/features/catalog/models/story_pack.dart`).
- Editing session state lives in plain mutable Dart objects (`AdminStoryNode`, `AdminChoice`,
  ...) loaded once per node selection and written back explicitly via "임시저장"/"승인 요청
  보내기" — deliberately not a live Firestore stream bound straight to the form, so incoming
  snapshot updates don't clobber in-progress typing. When editing widgets in `lib/admin/widgets/`,
  never derive a `Key` from a field's own live value (e.g. `ValueKey('id_${node.id}')` on the
  very TextFormField that edits `node.id`) — that recreates the field on every keystroke and
  breaks focus/cursor position. Key dynamic list items (choices, random-move candidates) by
  stable object identity (`ObjectKey(item)`), and key the whole editor subtree by the
  session's original selection id, not any live-edited field.
