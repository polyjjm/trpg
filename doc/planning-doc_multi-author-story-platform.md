# Multi-Author Story Platform — Planning Document

> Pivoted from the existing "ZOMBIE ROAD" project (a single zombie-survival battle game)
> to a content platform in the spirit of Millie's Library, combined with choice-based (gamebook-style) fiction.

## 1. Background of the pivot

- The existing codebase (`story_trpg` / ZOMBIE ROAD) was a single game with a battle system baked into the story
- Direction changed completely: now a **community where multiple authors post their own stories and readers pick what to read**
- The battle system is being removed — pivoting to a pure text (+ image) story platform
- Top priority: **build the system (platform) first** — content like the zombie story or short pieces is just example content to sit on top of it, not the goal itself

## 2. What's reusable from the existing codebase

- `lib/admin/` — an author/admin content editor already exists here. `AdminStoryNode`, `AdminChoice`, and the draft → pending-approval → live workflow, backed by the `storyPacks/{packId}/nodes` Firestore structure, can form the core skeleton
- `lib/features/story` — typewriter animation + choice rendering (foundation for the reader-facing viewer)
- Firebase auth / cloud save — reuse the existing account system as-is
- However, it currently uses a single-reviewer admin allowlist, so **the role system needs to expand to "anyone can become an author"**

## 3. Content (story) model

### 3.1 Story type (chosen by the author when registering a work)
- **Interactive (branching)**: has choices, the story splits into multiple paths. Can lead to several different endings (the group leaned toward true branching rather than a "converging" structure, since authors are expected to want real branches)
- **Linear (standard)**: a regular web-novel style read with illustrations, read straight through. Much simpler editor, lower barrier to entry

| | Interactive | Linear |
|---|---|---|
| Author editor | Nodes + choice linking | Chapters written in sequence with text + images |
| Reader screen | Choice buttons appear while reading | Just scroll / turn pages |
| Progress saved as | Which node the reader is on | Which chapter / % read |
| Ending | Can have multiple | One (completion) |

### 3.2 Genre
- Tag-based, multi-select (horror, romance, sci-fi, fantasy, thriller, slice-of-life, etc.)
- Type (interactive/linear) and genre are independent and combine freely (e.g. horror + interactive, romance + linear)

## 4. Presentation effects system

**"An option authors attach at the scene (node/chapter) level"** — designed as a shared system reusable across genres.
(A horror jump-scare and a romance confession-scene sparkle effect both run on the same underlying system)

- **Visual**: screen blackout/flash, shake, text effects (sudden enlargement, glitch/breakup, typing interruption)
- **Sound**: sound effects (SFX), background music (BGM) transitions
- **Haptic**: vibration (mobile)
- Trigger points: supports both "on entering a scene" and "on selecting a choice"

### Design principles (accessibility first)
- **Default is "none"** — fully opt-in. If the author touches nothing, it's a pure text-reading experience
- **Presets over parameters** — instead of numeric controls like a "duration slider," offer pre-tuned options like "light shake" / "strong shake." Non-developer, non-designer authors should be able to use this without friction
- **Preview is mandatory** — the author must be able to see/hear the result immediately after selecting, so they can choose by feel without needing to understand the underlying settings
- Rationale: this must never become a barrier to entry for pure-text writers. It's a "fun add-on," not a required skill

## 5. Text-to-speech (TTS) narration

- Offered as an **opt-in toggle** — never forced
  - Many reading contexts are silent (subway, office, etc.), and preferences differ between readers who want to read at their own pace and those who want an immersive listening experience
  - Horror readers in particular sometimes prefer "imagining the horror themselves while reading silently"
- MVP starts with TTS (AI voice) — applies fairly to every author/work at no cost
  - Real voice-actor recordings are costly and slow, so reserve that for a later stage (e.g. only for popular titles)
- Possible combination with effects: while TTS is on, a scene could have the narration tone drop or shift to a whisper, etc.

## 6. Market reference: "Okji's Exorcism Records" case

- A horror/occult spin-off born inside the world of "Bbangbbangi's Daily Life" (originally a gag/black-comedy webtoon and YouTube animation). Logged 2.6M+ views
- Takeaways:
  1. **The gap between a familiar character and an unfamiliar genre (horror)** is what generates buzz → potential value in letting characters/worlds cross genres
  2. It also spread via short-form video (YouTube Shorts/TikTok) → worth designing content that's easy to clip and share on social media
  3. Fandom-driven spread → potential value in features like "new release alerts for a popular author/character"

## 7. UI/UX principles

- **Minimal, whitespace-centered** — nothing should compete with immersion in the text; keep decoration to a minimum
- **Features stay quiet until needed** — choice buttons only appear after the text finishes revealing; text is the star the rest of the time
- **Color is used only to convey information, never for decoration** — e.g. a subtle signal like "this choice feels risky" (risky choice = red-leaning, safe choice = blue-leaning), not decorative coloring
- Top bar: minimal controls only (back, TTS toggle, menu)
- Bottom bar: quietly shows currently active effects + reading progress, nothing more

## 8. Still undecided / needs further discussion

### Reader experience
- Home/discovery feed (recommendations, popularity, new releases, genre filters)
- Story detail page (cover, synopsis, preview)
- Ending collection UI (gamified element for interactive works, e.g. "3 of 12 endings found")
- Managing progress across multiple in-progress stories

### Author experience
- Sign-up → becoming an author (automatic vs. application/review)
- Interactive-node editor UI (list-based vs. visual flowchart vs. hybrid — discussion leaned toward a list + preview hybrid, but not finalized)
- Draft/publish flow (adapting the existing admin draft → approval → live workflow for a multi-author structure)
- Author analytics dashboard

### Content rating / operations
- Given the horror genre, a need for violence/fear-level indicators (trigger warnings, age ratings)
- Support for serialized releases (weekly/daily chapters) vs. releasing a finished work all at once
- Whether to support collaborative authorship (multiple authors on one work, especially splitting branches between authors)
- Anti-piracy measures (screenshot prevention, watermarking, etc.)

### Social / monetization
- Comments, ratings, likes, following authors
- Free / paid / freemium-per-chapter, and whether there's revenue sharing for authors
- Reporting and content moderation

### Technical foundation
- Search, notifications (e.g. new-release alerts)
- Firestore schema redesign for multi-author support (`storyPacks` needs fields like `authorId`, `type` (interactive/linear), `genres`, plus effects- and TTS-related fields)

## 9. Suggested next steps

1. Flesh out the Firestore data schema based on this document (especially `storyPacks`, `users`, and the role structure)
2. Define the scope of expanding `lib/admin`'s editor for multi-author use
3. Design the information architecture for the reader's home/discovery/reader screens
4. Take the above into Claude Code for actual refactoring work
