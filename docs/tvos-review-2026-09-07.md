# tvOS application review — September 7, 2026

Scope: Apple TV navigation, library browsing, calendar, settings, and the shared data paths used by search/add/edit, downloads, and server controls. Existing service behavior was reviewed in source; simulator interaction used unconfigured services.

## Changes

- Bound custom focus highlights to their actual buttons in TV settings, calendar cells/events, and dashboard/library posters. This restores the intended focus outline as the remote moves between controls.
- Increased TV poster titles/subtitles, empty/error-state text, and release-filter labels for viewing at a distance. Added spoken calendar dates/event counts and filter states.
- Prevented URL/API-key entry from applying autocorrection or automatic capitalization.
- Removed the TV picker's stale cached option index and guarded empty option arrays, preventing division by zero and selecting from outdated options.
- Matched calendar weekday labels to the device's first weekday and locale. Previously a Monday-first grid could still have Sunday-first labels.
- Made the TV calendar column scrollable so six-week months remain reachable. Adjusted the month header to avoid truncating the month/year.
- Restricted media links to positive server library IDs. Previously an earlier item's overlapping TMDB/TVDB ID could open the wrong movie/show. Invalid IDs and extra path segments are rejected.

## Validation

- Added regression tests for Sunday/Monday/Saturday calendar headings, overlapping external media IDs, and malformed media links.
- Added Apple TV remote navigation coverage for all main tabs, six-week calendar traversal, and opening/cancelling the server URL editor.
- Kept iPhone/iPad-only UI tests out of the tvOS compilation path.
- tvOS 26.5 simulator: 34 unit tests and the remote UI test passed (0 failures).
- iOS 26.5 simulator: 34 unit tests and the iPhone navigation/settings UI test passed (0 failures).
- Property-list/entitlement lint and `git diff --check` passed.
- Final screenshots confirm the full month/year is visible and remote focus reaches the last row of a six-week month. Xcode stalled collecting optional simulator diagnostics after the TV tests; stopping only that collector allowed the result bundle to finish with `TEST SUCCEEDED` and exit code 0.
- Result bundles: `/tmp/media-tvos-audit/Logs/Test/Test-Media Manager-2026.09.07_20-17-34--0400.xcresult` and `/tmp/media-ios-audit/Logs/Test/Test-Media Manager-2026.09.07_20-17-35--0400.xcresult`.

## Limits

The simulator checks do not verify a physical Siri Remote, populated live libraries, trailer playback, actual downloads, or live server mutations. No release upload, deployment, or production configuration change was performed. Existing concurrency warnings in older unit tests remain outside these changes.
