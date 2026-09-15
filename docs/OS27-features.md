# OS 27 adoption with OS 26 compatibility

Implemented with Xcode 27.0 (27A266a). Version 3.0, build 19. Existing deployment targets are retained.

## Features

| Area | OS 27 | OS 26 |
| --- | --- | --- |
| Library Assistant | Home toolbar opens combined movie/show search. Core Spotlight supplements literal matches with ranked semantic results. On-device Foundation Models answers questions using a bounded metadata sample. | Existing library/search navigation remains available; the assistant entry is hidden. |
| Image identification | Photo picker and image prompts appear only when the available on-device model advertises vision support. Identification suggests a title; it does not add anything. | Existing manual discovery/add flows. |
| Siri and Shortcuts | Official `.system.searchInApp` schema routes to library search. Movie/show screens and discovery review sheets expose entity identifiers. | Existing shortcuts continue to work. |
| Exact title actions | Typed Add Selected and Open actions use TMDB/TVDB identities, with real identifier resolution and string queries. | The same identity and ambiguity fixes work on OS 26. |
| Spotlight | Indexes library titles, years, descriptions and networks. Applies incremental updates and removes deleted entries. | New indexing/search integration is gated off. |
| Navigation | System navigation/tab appearance, retaining the app's content styles. | Existing appearance customization. |
| Upcoming widget | Configuration offers all releases, movies only or TV shows only; retains the widget kind and default content. | Configuration works here too through existing WidgetKit APIs. |
| Watch summary | Explicit Summarize action asks the paired iPhone for current library/queue facts, with an optional on-device rewrite. | Existing Watch dashboard and actions. |

AI requests never mutate the library. Prompts exclude server URLs, keys and filesystem paths. Missing model support, generation failures and Watch connection failures have explicit fallbacks. Library responses use a limited title sample and are instructed not to infer absence from that sample.

## Apple API boundaries

- The shipping SDK has no dedicated movie/TV catalog-add schema for Radarr/Sonarr. These remain custom App Intents; `.system.searchInApp` is adopted only for the matching search action. Full conversational Siri coverage must not be claimed from a build alone.
- Screen associations use the SDK's `appEntityIdentifier` modifier. `viewAnnotations()` is the App Intents Testing inspection API.
- The on-device `SystemLanguageModel` is unavailable on watchOS. Watch summaries use the paired iPhone; no Private Cloud Compute entitlement or paid provider is required.
- Private Cloud Compute requires Apple's managed entitlement and eligibility approval. It is not enabled by this change.
- Media Manager does not implement playback, so this change does not introduce a NowPlaying integration.
- Semantic ranking, natural-language Siri behavior, image-identification accuracy and paired-device delivery still require device testing under the user's language, model and network conditions.

## Validation

Verified on September 15, 2026:

- iOS 26.5: 73 tests passed on the final tree (72 unit tests and the availability/navigation UI test). The broader navigation/settings test also passed in the preceding 74-test run.
- tvOS 26.5 and tvOS 27.0: 72 unit tests passed on each runtime.
- iOS 27.0: 74 tests passed on the final tree (72 unit tests and two UI/system tests). The synthetic system test verified catalog ID 800, its detail-screen annotation and its Spotlight entry. The assistant UI was visually inspected.
- iOS device-SDK and simulator builds passed, including the Watch app and widget extension. These are build checks, not physical-device tests.
- Test runs emitted non-failing SwiftUI state-publication warnings. Live Siri phrasing, model accuracy and paired Watch delivery are not established by these checks.

Final result bundles:

- `/tmp/media-os27-complete.xcresult`
- `/tmp/media-ios26-complete.xcresult`
- `/tmp/media-ios26-verified.xcresult` (includes broader navigation/settings coverage)
- `/tmp/media-tvos26-tests.xcresult`
- `/tmp/media-tvos27-tests.xcresult`

The combined iOS 27 run stalled in `simctl diagnose` after all tests finished. Only the diagnostic collector was stopped; Xcode then exited successfully and its finalized result bundle reports 74 passed, zero failures. Diagnostic collection is therefore incomplete for that run.

Normal unit/UI tests build without the OS 27-only App Intents Testing dependency. For the OS 27 system integration test, explicitly set:

```sh
xcodebuild -project 'Media Manager.xcodeproj' -scheme 'Media Manager' \
  -destination 'platform=iOS Simulator,id=<OS27_DEVICE_ID>' \
  -parallel-testing-enabled NO \
  -only-testing:'Media ManagerUITests/Media_ManagerUITests/testSystemMovieEntityQuery' \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG MEDIA_APP_INTENTS_TESTING' test
```

Do not use this compilation condition for OS 26 tests: Apple's test framework depends on OS 27 system libraries. Use signed simulator builds so CloudKit and Keychain retain their required entitlements.

The integration fixture is Debug-only, activated by `--media-intelligence-fixtures`. It serves a synthetic movie from an intercepted `.invalid` host, rejects non-GET requests, and never contacts production services.

### Official references

- [iOS 27 developer overview](https://developer.apple.com/ios/whats-new/)
- [Search-in-app schema](https://developer.apple.com/documentation/appintents/appschema/systemintent/searchinapp)
- [Private Cloud Compute model](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel)

## Siri add-flow review

- Quick Add App Shortcuts now expose movie/show entity parameters with title-bearing phrases (for example, “Add the movie [title] to Dragon Media Manager”). The original prompt-first phrases and existing custom intent types remain available. App activation refreshes shortcut parameters.
- Selected-title actions use the saved-default Quick Add path instead of forcing search and all-season monitoring. The ordinary configurable Add actions retain their explicit search/monitor parameters.
- Follow-up choices include catalog IDs only for identical title/year labels. Invalid and duplicate catalog IDs are removed from results, and typed catalog lookups remain exact.
- Siri interaction and cancellation errors propagate to App Intents. Only a typed duplicate-title error returns the already-in-library response; root-folder/profile failures remain failures. Missing server add options stop before a POST.
- Successful adds update local library state and its Spotlight integration.
- Real-device Siri recognition, ambiguous-title follow-up dialogue, and server-backed addition still require a physical-device check. Registration and simulator tests do not prove arbitrary conversational Siri support.

Apple references: [EntityQuery](https://developer.apple.com/documentation/appintents/entityquery), [App Shortcuts parameter phrases](https://developer.apple.com/videos/play/wwdc2022/10170/), [system interaction cancellation](https://developer.apple.com/videos/play/wwdc2025/275/).

Review validation: 75 unit tests passed on iOS 26.5 (`/tmp/media-siri-final26.xcresult`) and 75 on iOS 27.0 (`/tmp/media-siri-final27.xcresult`), including regression cases for colliding spoken labels, invalid/duplicate catalog IDs, and duplicate-error classification. The tvOS simulator build passed (`/tmp/media-siri-tvos.log`). Generated `extract.actionsdata` contains both selected-title actions and their parameterized phrase templates.
