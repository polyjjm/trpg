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

The old hardcoded `features/story/widgets/story_page.dart` (`StoryPage`) has been retired — it rendered the hand-written `features/story/data/story_nodes.dart` content directly. That file's actual node content is no longer read by anything, and its `storyStartNodeId` sentinel constant (`'intro_01'`) is now unused dead code too (kept, not deleted) — `GameState` no longer takes a `startingNodeId`/keeps a global `currentNodeId` at all; per-pack read position now lives in `GameState`'s `Map<String, ReadingProgress>` (see "Reader system" below), so this old sentinel has nothing left to feed. `EncounterPage` itself is no longer routed to from anywhere in the app — it's dead code that hasn't been deleted, not an active screen.

### Reader system (`lib/reader/`)

Real per-pack content flows from Firestore (`storyPacks/{packId}/nodes`, reading each node's `liveSnapshot` — the last-approved content, never the top-level "currently editing" fields, same pattern as `StoryPackRepository`'s `liveMetadata`) via `StoryReaderRepository` (`lib/reader/shared/data/story_reader_repository.dart`), which also resolves each node's background image through the inheritance chain (`lib/core/story/background_image_inheritance.dart`: explicit node value → nearest earlier node by `order` → `storyPack.defaultBackgroundImage` → none, recomputed at **read time**, never baked in at write time — see "Node content schema" below for why) and joins `images/{imageId}` docs to real URLs.

`SceneFrame` (`lib/reader/shared/scene_frame.dart`) is the shared full-screen node renderer both reader types build on: it types out `blocks` (paragraph/beat/image) in order, fades in a background banner, and — once typing completes — fades in a type-specific action area supplied by the caller via `actionAreaBuilder`. It also owns a collapsible bottom settings sheet (TTS play/pause via `lib/reader/shared/tts_controller.dart` wrapping `flutter_tts`, BGM mute via `AudioService`, font selector, typing-animation toggle) backed by a per-user `users/{uid}/readerPrefs/settings` Firestore doc (`ReaderPrefsRepository`, `lib/reader/shared/data/reader_prefs_repository.dart`).

- `InteractiveReader` (`lib/reader/interactive/`): `storyPack.type == 'interactive'`. Renders `node.choices` as buttons; tapping one calls `GameState.recordNodeVisit(packId: ..., nodeId: choice.nextNodeId)` and swaps to that node in place (no new route per node).
- `LinearReader` (`lib/reader/linear/`): `storyPack.type == 'linear'`. Renders a single "다음" button following `node.nextNodeId`, or "완료" when it's null.
- Both reuse `GameState.ownsPack`/`previewNodeLimit` for the free-preview paywall (`lib/reader/shared/paywall.dart`), now reading the per-pack `visitedNodeCount` off `GameState.progressFor(packId)` (see below) instead of a global counter.
- **Per-pack reading progress**: `GameState` holds `Map<String, ReadingProgress> _readingProgress` keyed by `packId` (`lib/core/state/reading_progress.dart`) — `currentNodeId`/`visitedNodeCount`/`lastReadAt` per pack, replacing the old global `GameState.currentNodeId`/`visitedNodeCount` scalars (a previously-documented known limitation, now fixed). Signed-in users get this persisted to `users/{uid}/readingProgress/{packId}` via `ReadingProgressRepository` (`lib/core/state/reading_progress_repository.dart`) — written directly by `InteractiveReader`/`LinearReader` at the same point they call `recordNodeVisit`/`resetPackProgress`, not through `CloudSyncController` (which only still owns the single `users/{uid}/save/current` blob — inventory/level/hearts/cash/ownedPackIds — via `GameState.toJson()`/`loadFromJson()`, schema v6+, which no longer carries `currentNodeId`/`visitedNodeCount` at all). Guest/signed-out play keeps the same map purely in memory — separate per pack within the session, gone on restart, same as the rest of guest `GameState`. On opening a reader, if `GameState.progressFor(packId)` is empty it falls back to a Firestore lookup (signed-in only) before defaulting to the pack's first node; `StoryPackDetailPage` does the same lookup proactively so its "이어보기"/"읽기 시작" button label and 진행률 metadata reflect the real per-pack signal instead of the old global placeholder.
- Both readers implement all four `effects` scene-presentation types (blackout/shake/sfx/haptic) plus the newer `flash` type — see "Node content schema" below. `SceneFrame` fires every enabled effect concurrently (fire-and-forget, no `await` chain between them) exactly once per node visit, right as `actionAreaBuilder` fades in.

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
  `admin/story_images/**`.
  **Rules are live and enforcing access** — a `firestore.rules` file exists at the repo root
  and has been published via the Firebase console (role-based, same shape as the
  `FIRESTORE_SCHEMA.md` snippet), including a fix to the admin approve/reject equality-check
  rule after the blocks-schema migration broke it (the rule was still comparing old flat
  fields — `title`/`day`/`body`/`bgImageId` — that no longer exist on migrated node docs,
  which made every approve/reject fail with `permission-denied` until the rule was updated to
  check the new field names instead: `order`/`blocks`/`backgroundImage`/
  `backgroundAppliesForward`/`choices`/`nextNodeId`). Storage rules for
  `admin/story_images/**` have also been published via console.
  **Rules are still managed by hand in the Firebase console, not from a file in this repo** —
  no `storage.rules` file exists here at all, and the checked-in `firestore.rules` has already
  drifted from what's actually deployed (it still shows the pre-migration field list). Don't
  treat either file's presence/absence as evidence of what's currently enforced; when in doubt,
  check the console directly.
- The game reads these collections for real play now — see "Reader system" above
  (`StoryReaderRepository` reads each node's `liveSnapshot`, joined with `images/{imageId}` for
  URLs). Keep the naming caveat in mind though: `lib/admin/models/admin_story_pack.dart`
  (admin's editing-session model) and `lib/features/catalog/models/story_pack.dart` (the
  reader catalog's card model) are unrelated Dart classes that happen to share a name — don't
  confuse them.

### Node editing session: mutable local state + browser-tab autosave

Editing session state lives in plain mutable Dart objects (`AdminStoryNode`, `AdminNodeBlock`,
`AdminNodeChoice`, ...) loaded once per node selection — deliberately not a live Firestore
stream bound straight to the form, so incoming snapshot updates don't clobber in-progress
typing. Writing to Firestore still only happens explicitly, via "임시저장"/"승인 요청 보내기".

On top of that, switching between nodes, story packs, or tabs mid-edit **no longer discards
unsaved changes**. `NodeEditSessionCache` (`lib/admin/data/node_edit_session_cache.dart`) is a
plain in-memory cache keyed by `(packId, nodeId)`, owned by `AuthorToolPage` (so it survives
`StoryTabView` being torn down and rebuilt on every pack switch) and threaded down into
`StoryTabView`. Every field edit writes the current `AdminStoryNode` into the cache; opening a
node checks the cache before falling back to `fetchNode()`. Multiple nodes can have independent
unsaved buffers open at once — switching A → B → back to A restores A's edits. The cache is
purely in-memory: it does not survive a tab refresh or close (an accepted limitation, not a
regression from before this existed), and an entry is cleared the moment that node is
successfully saved (either 임시저장 or 승인 요청). The sidebar shows a small "수정됨" badge next
to any node with a live cache entry.

This replaced an earlier design that tried to block navigation with an unsaved-changes
confirmation dialog — that approach had real bugs (a `ValueKey` collision after the node-ID
auto-suggestion fix meant creating a second unsaved draft could silently reuse the same widget
key as the first, so Flutter never remounted the text field; separately, the confirm callback
wasn't reliably resuming the original action after the user confirmed). The autosave cache
sidesteps the whole class of problem — there's nothing to discard, so nothing to confirm.

When editing widgets in `lib/admin/widgets/`, never derive a `Key` from a field's own live
value (e.g. `ValueKey('id_${node.id}')` on the very `TextFormField` that edits `node.id`) —
that recreates the field on every keystroke and breaks focus/cursor position. Key dynamic list
items (choices, random-move candidates) by stable object identity (`ObjectKey(item)`), and key
the node editor subtree by the **edited node's object identity** (`ObjectKey(editingNode)`),
not a string id — two different unsaved drafts can legitimately share an id (e.g. the "+" button
suggests the same next id again if the first draft was abandoned before saving), and keying by
id alone means Flutter treats them as "the same widget" and never remounts the text fields.

New node ids default to a sequential-pattern suggestion (`suggestSequentialNodeIds`,
`lib/admin/data/node_id_suggestion.dart` — detects a `prefix + number` pattern in existing ids,
e.g. `노드1` → `노드2` → `노드3`, falling back to `node_1` if nothing matches). The suggestion
only ever looks at **persisted** Firestore node ids, plus any other still-unsaved drafts already
sitting in the session cache for that pack — never a display list that mixes the two — otherwise
an unsaved draft would get counted as if it already existed and the next suggestion would skip
a number.

### Node content schema

Beyond `blocks`/`choices`/`nextNodeId` (see the reader/admin node-shape notes elsewhere in this
file), nodes carry:
- `order` (int): position for the background-image inheritance chain (see "Reader system"
  above) and for drag-and-drop reordering in the admin sidebar (`StoryNodeSidebar`, backed by
  `ReorderableListView`). Reordering rewrites `order` on every node whose relative position
  actually changed, but — like every other edit — stages the change in the session cache rather
  than writing Firestore instantly; it still needs 임시저장/승인 요청 like any other edit.
  Because the inheritance chain is recomputed at **read time** from whatever's currently in the
  session cache (not baked in at write time), the "이 노드부터 배경이 바뀔 때까지 이어져요" hint
  in the node editor updates immediately after a drag, before you've saved anything.
- `backgroundImage` (nullable images/{imageId} reference) + `backgroundAppliesForward` (bool,
  default `true`): whether this node's explicit background choice keeps propagating forward to
  later nodes that don't pick their own, or applies to this node only. Editable via a checkbox
  in `NodeEditor`, directly under the 배경 이미지 field (not boxed off — reads as one of that
  field's own options).
- `effects` (nullable, preset-only): scene-presentation effects — `blackout`
  (`{enabled, durationPreset: 0.5s|1s|2s}`), `shake` (`{enabled, intensityPreset: 약하게|보통|강하게}`),
  `sfx` (`{enabled, sfxId: string?}` — a `sfxLibrary/{sfxId}` reference, not a fixed preset; see
  "SFX library" below), `flash` (`{enabled, colorPreset: 빨강(피격)|하양(섬광)|파랑(냉기),
  durationPreset: 짧게|보통|길게}`), `haptic` (`{enabled, durationPreset: 짧게|길게}`) — modeled in
  `lib/admin/models/node_effects.dart`, edited via a collapsible "연출 효과" section in `NodeEditor`
  (`lib/admin/widgets/node_effects_editor.dart`), a peer of the 배경 이미지/본문/선택지 sections,
  not a separate tab. Deliberately preset-only (except `sfx`, which points at an uploaded library
  file), so non-developer authors never have to guess at a value. **Playback is fully wired up**:
  the reader has its own parallel model (`lib/reader/shared/models/node_effects.dart` — never
  imports `lib/admin/`) and `SceneFrame` (`lib/reader/shared/scene_frame.dart`) triggers every
  enabled effect concurrently, exactly once per node visit, the moment typing finishes — blackout/
  flash render as independent `AnimatedOpacity` color overlays in `SceneFrame`'s `Stack`, shake as
  a decaying-sine `Transform.translate` via an `AnimationController`, sfx via
  `AudioService.instance.playSfx` (resolved `sfxId → storageUrl` through the same join pattern as
  `backgroundImage`, in `StoryReaderRepository`), haptic via `HapticFeedback`.

### Image library

Images (`images/{imageId}`, shared across all packs/authors — not per-pack) carry a
`category` field: `배경`/`선택지`/`기타`, a fixed enum chosen at upload time (defaults to
기타 if skipped), not free-form tags or folders. The library grid (`ImageLibraryTab`) shows
filter chips with live counts per category; the same category filter narrows
`ImagePickerField`'s dropdown wherever it's used with a `filterCategory` (currently: node and
pack default background pickers, both scoped to `배경`). A "카테고리 변경" action per card
re-tags an image after the fact — useful for images uploaded before this field existed, which
read as 기타 by default.

### SFX library

Mirrors the image library pattern: `sfxLibrary/{sfxId}` (shared across all packs/authors — not
per-pack) is a lightweight Firestore index (`name`/`category`/`storageUrl`/`uploadedBy`/
`createdAt`) pointing at a file under Storage `admin/story_sfx/{sfxId}.mp3` (fixed extension in
the path, unlike images which keep the original filename). `category` is a fixed 5-value enum
(문/발소리/비명/심장박동/기타), edited in the "효과음 라이브러리" tab (`SfxLibraryTab`,
`lib/admin/pages/sfx_library_tab.dart`) — filter chips + live counts + name search
(`LibrarySearchField`, shared with `ImageLibraryTab`'s own search box) + upload (`file_picker`'s
`FileType.audio`) + a per-card preview-play button (`AudioService.instance.playSfx`, which
already spins up a short-lived `AudioPlayer` per call, independent of the BGM player). The node
editor's SFX picker (`SfxPickerField`, `lib/admin/widgets/sfx_picker_field.dart`) is the
`ImagePickerField` pattern adapted the same way — thumbnail slot replaced by a play button, plus
its own category filter chips baked in (unlike `ImagePickerField`, which is always called with a
single fixed `filterCategory` from its call site).

### Bulk content entry (linear packs)

A "한 번에 쓰기" toggle in the node editor (`_BulkModeToggle` in `story_tab_view.dart`) swaps
the usual sidebar+editor for `BulkNodeWriter` (`lib/admin/widgets/bulk_node_writer.dart`): paste
one long block of text, set a per-page character limit, and preview how it splits into pages.
The split only ever happens on paragraph boundaries (`splitIntoParagraphs`, the same rule the
single-node body editor uses) — a paragraph longer than the limit becomes one oversized page
rather than being cut mid-sentence. Saving creates one `AdminStoryNode` per page with an
auto-assigned sequential id (same `suggestSequentialNodeIds` as the "+" button), chained via
`nextNodeId`, and writes them all in a single atomic `firestore.batch()`
(`AdminStoryRepository.saveNodesBatch`). Still goes through the same draft/approval gate as
everything else — `pendingAction: create`, `status` stays `draft` until an admin approves.

### Batch review actions

Two independent batch-selection features, both checkbox-driven:
- **승인 대기함** (`lib/admin/pages/approvals_tab.dart`, admin-only): multi-select pending
  create/edit/delete requests and approve them all in one click.
- **Node sidebar** (`story_tab_view.dart`'s `_handleBulkDelete`/`_bulkDeleteSelection`): select
  multiple nodes and delete them together — drafts that were never published are deleted
  immediately, already-published nodes get a delete request queued instead (same split logic
  as deleting one node at a time).

### Light/dark theme

`AdminTheme` (`lib/admin/widgets/admin_theme.dart`) holds a `ValueNotifier<ThemeMode>`
persisted via `shared_preferences` (silently falls back to dark if storage is unavailable, e.g.
a private-browsing tab), toggled by a small icon button (`_ThemeModeToggle` in
`author_tool_page.dart`). `AdminColors`' core palette (`bg`/`panel`/`panel2`/`border`/`ivory`/
`muted`) are **getters** keyed off `AdminTheme.isDark`, not `static const` — the rest
(`gold`, status/approve/reject colors, etc.) stay `static const` by design, meant to look the
same in both modes.

**Gotcha worth knowing before adding new widgets under `lib/admin/widgets/`**: Flutter resolves
a widget's own inline color properties (`Checkbox.fillColor`, `TextFormField`'s
`InputDecoration.fillColor`, etc.) *before* falling back to `ThemeData`'s sub-themes
(`checkboxTheme`, `inputDecorationTheme`) — so pointing `ThemeData` at a light/dark swap alone
doesn't reach any widget that sets those properties explicitly, which nearly everything in this
codebase does. Making the toggle actually work meant converting hardcoded `Color(0x...)`
literals to `AdminColors.xxx` getters across every widget that had them, not just adding a
theme. If you add a new widget with an inline color property, pull it from `AdminColors` (or
add a new getter there) rather than hardcoding a `Color(...)` — a hardcoded value will silently
ignore the toggle.
