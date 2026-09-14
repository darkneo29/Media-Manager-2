# Apple TV UI design review

The design now prioritizes browsing at a distance and deliberate remote actions. The existing navigation destinations and purple/cyan visual identity remain familiar.

## Design changes

- A dedicated TV typography scale replaces shared phone-sized labels across Home, Discover, details, downloads, server views, and forms. iOS retains its original sizes.
- Movie and show libraries have a clear action row: Search, Collections or Filter, Select, Add, and Refresh. Opening a library no longer brings up a keyboard automatically.
- Poster grids use six larger, evenly aligned cards per row. Two-line title slots keep mixed title lengths from making the posters stagger vertically.
- Add Options opens a full-screen, scrollable panel with a fixed Done action. Search results keep the screen space previously occupied by all the option rows. Loaded options remain reactive, and reopening a panel does not reset edits.
- Movie and show details expose Edit beside the title, without requiring a trip to the bottom of the page.
- Review/add and edit forms use the TV canvas; Quick Add has a labelled Close button instead of a touch-only drag handle.
- Edit forms use explicit selected-value menus and On/Off buttons on TV, fixing blank native picker/toggle labels.
- Download, file, and server action targets are larger. Bulk library actions have visible labels on TV. Configuration empty states offer Open Settings.
- Custom focus outlines make the selected control clear. Custom focus scaling respects Reduce Motion. Picker/toggle rows use real buttons with accessible labels and values.
- The calendar allows room for focus effects around the scrolling month grid.

## Validation approach

An explicit Debug-only offline fixture mode exercises the production views with sample movie/show libraries, local abstract poster artwork, quality profiles, folders, and downloads. It runs in the separate **Media TV Design Review** simulator. Every HTTP request in that mode is intercepted; no live server operations are performed. The fixture entry point and implementation are excluded from Release builds.

The remote UI scenario covers populated libraries, explicit search, add options and profile selection, downloads, movie/show details, and editing. A second scenario covers unconfigured main-tab navigation, six-week calendar scrolling, and server settings. Shared changes are checked with the iOS unit and navigation tests.

## Results

- tvOS: signed Debug build, 34 unit tests, unconfigured navigation/settings UI scenario, and populated remote UI scenario passed. The final populated run verifies opening Edit from the hero and a visible loaded quality-profile value.
- iOS: signed Debug build and 34 unit tests passed after the final TV form changes. The main-navigation/server-settings UI scenario also passed earlier in this review.
- All five plist/entitlement files passed lint; `git diff --check` passed.
- Final populated evidence: `/tmp/media-tvos-design/Logs/Test/Test-Media Manager-2026.09.07_20-41-16--0400.xcresult`.
- Final iOS unit evidence: `/tmp/media-ios-audit/Logs/Test/Test-Media Manager-2026.09.07_20-41-26--0400.xcresult`.
- The earlier combined tvOS run exposed the hard-to-reach Edit action. The final focused scenario passes after the hero action and form-control fixes. The passing unit and unconfigured-navigation results came from the combined run.

## Screenshots

These are unaltered 4K simulator captures with offline sample data.

[Movie library](tvos-design/movie-library.png) · [Show library](tvos-design/show-library.png) · [Add options](tvos-design/add-options.png) · [Edit movie](tvos-design/edit-movie.png) · [Movie details](tvos-design/movie-details.png) · [Show details](tvos-design/show-details.png) · [Downloads](tvos-design/downloads.png)

## Design references

The direction follows Apple's guidance on [designing for tvOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos/), [typography](https://developer.apple.com/design/human-interface-guidelines/typography), and [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

## Boundaries

The screenshots use fictional titles and abstract sample artwork. A physical Siri Remote, real service latency, live trailer playback, and production server mutations are not validated by these simulator checks. The UI review itself did not upload a release. The subsequent [2.11 (15) TestFlight release](tvos-testflight-2.11-15.md) is now available internally and awaiting external beta review.

## Branding follow-up

TV home-screen and App Store icon assets now reuse the current iOS red dragon/play artwork. Both Top Shelf sizes reuse the iOS launch artwork. The shared launch overlay uses aspect-fit on TV so the full logo and title remain visible on a landscape screen; iOS keeps its existing presentation.

Run `bash scripts/sync-tvos-branding.sh` after replacing the iOS source artwork to regenerate the TV asset sizes. This only resizes and pads the existing artwork. The current iOS icon contains an opaque checkerboard background, which is preserved in the TV copies.

Both iOS and tvOS Debug builds passed after this update. [Actual TV launch screenshot](tvos-design/launch-screen.png). Version remains 2.11 (15).
