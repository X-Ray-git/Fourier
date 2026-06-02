# Changelog

All notable changes to this project will be documented in this file.

## [1.1.4] - 2026-06-02

### Fixed
- Prevented timeline article cards from rendering as release gray error boxes when local AI cache boxes are not hydrated yet.
- Added pagination guards for Folo entry collection to avoid staying on the loading surface if a page repeats or the cursor stops advancing.

## [1.1.3] - 2026-06-02

### Fixed
- Switched Android internal release builds to a fixed keystore supplied through GitHub Secrets, avoiding APK install conflicts caused by per-environment debug signing keys.

## [1.1.2] - 2026-06-02

### Added
- Added editable Summary and Translation system prompts in Settings, with `{targetLang}` template substitution.

### Fixed
- Preserved AI filter queue order by recording `filteredAt` and appending new rejected articles to the review list.
- Backfilled Inbox detail content before readability and AI processing, while only marking detail fetch success after non-empty content is stored.
- Kept AI filter metadata stable across local article content updates and shared one direct cleanup path for rejected article recovery/read handling.

## [1.1.1] - 2026-06-01

### Added
- Added macOS desktop release packaging and Android APK packaging through tag-triggered GitHub Actions.
- Added macOS sidebar-oriented reading flow, task center access, and desktop-focused sync feedback.

### Fixed
- Fixed macOS split-view keyboard shortcuts so left/right navigation and `M` read-state toggling work without focus glitches or double triggers.
- Fixed rejected/unread review counts and subscription unread badges drifting after read-state sync.
- Updated product branding and macOS app bundle display name to Auto Folo.

## [1.1.0] - 2026-05-26

### Added
- **Performance**: Introduced Isolate-based background rendering for HTML parsing, ensuring butter-smooth swipe transitions (60/120fps) between articles.
- **UI State Sync**: Re-engineered `TimelineController` to use fine-grained `ArticleStateNotifier` updates, resolving issues where AI-filtered or read articles would drift out of sync with the UI without a manual refresh.

### Fixed
- **Rich Text & Tables**: Re-integrated `flutter_html_table` and fixed HTML chunk parsing to restore missing tables and perfectly preserve inline rich text (bold, links, images) within lists.
- **Clickable Links**: Restored interactivity for nested links (e.g., inside headings or quotes) by using `outerHtml` parsing instead of stripping them down to pure text.
- **Inbox Caching**: Rewrote the `_trimOverflow` logic in `LocalArticleDbService` with a priority queue to protect ancient but unread Inbox items from being prematurely evicted by the 5000-article cache limit.
- **Adaptive Images**: Lifted the hardcoded `maxWidth` restriction for inline icons, fixing issues where WordPress emojis were stretched and ruined layout proportions.
