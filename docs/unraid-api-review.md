# Unraid API integration review

Reviewed September 14, 2026 for Unraid 7.3.0 and newer against the official API schema and Docker resolver.

## Commands

The client posts JSON to `/graphql` with `x-api-key`. IDs are opaque: preserve the exact returned `id`, including prefixes and punctuation, in GraphQL variables.

```graphql
mutation RestartContainer($id: PrefixedID!) {
  docker {
    result: restart(id: $id) { id state status }
  }
}
```

Start and stop use the same structure with `start` or `stop`. Native restart was added in API 4.36.0; OS version alone does not determine API capabilities because the Connect plugin can supply newer API releases. If the server explicitly rejects the missing restart field during schema validation, the client awaits stop and then start. Other errors never trigger a second restart attempt.

VM actions use `vm { result: start(id: $id) }`, with `stop`, `forceStop`, `reboot`, `pause`, or `resume` as appropriate. The Boolean result must be true. The UI passes the returned domain ID instead of the deprecated UUID field.

## Corrections

- Removed ID filtering that discarded punctuation from prefixed IDs.
- Increased command timeouts from 15 to 120 seconds.
- Invalidated cached status both before and after commands, including failures.
- Preserved GraphQL error messages for HTTP 400 validation responses and partial data.
- Rejected missing command results and false VM results.
- Displayed Docker command errors to users and ignored repeated taps during an operation.
- Clarified that viewer access is sufficient for monitoring, but controls need update permission.

A client timeout does not establish whether a command completed on the server. No automatic retry follows a timeout. The stop/start compatibility fallback can leave a container stopped if the subsequent start fails; the error explains that outcome.

## Sources

- [Official API availability](https://docs.unraid.net/API/)
- [Official schema](https://github.com/unraid/api/blob/main/api/generated-schema.graphql)
- [Docker mutations and permissions](https://github.com/unraid/api/blob/main/api/src/unraid-api/graph/resolvers/docker/docker.mutations.resolver.ts)
- [API 4.36.0 release](https://github.com/unraid/api/releases/tag/v4.36.0)

Mock HTTP regression coverage exercises native restart, exact ID preservation, missing-field compatibility fallback, authorization/errors without retries, missing results, partial errors, and false VM responses. This does not verify a restart against a live Unraid server.

## Full integration and performance review

The second pass covered the service, response models, server screen, dashboard health card, Docker/VM cards, connection settings, Siri status intent, and Unraid participation in backup/cloud settings flows.

### Additional changes implemented

| Area | Finding and correction |
| --- | --- |
| Cache correctness | The five-second cache was global to the service and configuration invalidation was asynchronous. Cache and in-flight task selection are now atomic and keyed to the exact endpoint/key. Results from superseded credentials are rejected. Explicit refresh bypasses completed cached results while still sharing an in-flight read. |
| Command routing | A stop/start fallback could read newly changed settings between steps. The complete restart sequence now retains its original endpoint/key. VM requests also capture credentials before awaiting cache invalidation. |
| Schema compatibility | Disk name/size/status and VM name/UUID can be null. Models accept the nullable fields; VM queries now use ID and omit deprecated UUID. Memory BigInt fields accept numeric and string representations. Boot disks are no longer classified as data disks. Storage conversion/summation cannot overflow. |
| Request size and maintenance | Centralized repeated field selections and system mapping. Removed unused online, disk-count, fsFree, and deprecated UUID selections. Removed the unreachable Docker fallback that could not run after the transport threw a GraphQL error. |
| UI command state | Removed fixed two-second busy timers. Start, stop, and restart remain busy until completion; repeated commands are ignored in the same screen. VM errors now appear alongside Docker errors. Paused resources use unpause/resume instead of start. Navigation away does not cancel an issued command midway through stop/start. App termination or suspension can still interrupt network work. |
| Freshness | Failed refreshes show a warning with retained data, instead of silently appearing current. Server-screen publication uses generation checks. Credential changes restart loading. |
| Dashboard lifecycle | One lifecycle-bound task performs initial load/retries and periodic refresh; polling pauses while inactive/hidden. Nontransient initial errors do not use the network retry loop. The status label identifies array state rather than calling a stopped array an offline server. |
| Metrics | CPU utilization is now displayed, not only core count. Missing CPU/RAM metrics are labelled unavailable in the card and Siri. Percentages are bounded. |
| Settings and transport | Accepts a base URL or `/graphql` endpoint without duplicating the path. Rejects invalid schemes and URL credentials/query/fragment. Settings save errors are surfaced on explicit back/save. Requests bypass URLSession response caching and cookies; API-key permissions are authoritative. HTTP 403 is distinguished from an invalid key. Response payloads are no longer dumped on decode failures. |

Backup and cloud settings already include Unraid credentials/preferences and apply credentials before publishing URL changes. No backup-format or encryption change was needed. The new request identity protects reads after those flows refresh configuration as well.

### Priority changes implemented for 3.0 (16)

1. **Independent summary and detail reads.** Dashboard and Siri request hardware, metrics, array capacity/state, and container IDs/states. They omit disk inventory, VM domains, images, and other container metadata. The server screen adds separate disks, containers, VM, and parity sections. A failed resolver retains its previous value with an error and timestamp; an unavailable list is not labelled empty or zero. CPU/RAM remain available to Siri when hardware lookup fails, and container counts remain available when storage fails. The former monolithic snapshot path has been removed.
2. **Capabilities and permissions.** The connection test and server refresh discover schema fields, authenticated roles/resource permissions, and API version, cached per endpoint/key. Known denied or unsupported actions are disabled. Missing introspection or identity permissions are represented as unknown, with the server remaining authoritative; they do not prevent baseline monitoring. Native Docker restart support is cached, with the start/stop compatibility path retained. Manual refresh rechecks access after an API upgrade or key change.
3. **Independent refresh clocks.** Successful section results and in-flight requests are shared per endpoint/key. Hardware is retained for 300 seconds, disk inventory 120, storage/parity 30, containers/VMs 15, metrics 10, and discovery 600. The dashboard checks every 30 seconds; the server screen every 10 while visible and active. Manual refresh bypasses completed values but shares in-flight work. Read failures back off, HTTP 429 honors Retry-After across sections, and superseded credential results cannot publish. Commands invalidate only affected resource status.
4. **Operational diagnostics.** Container details display the latest 200 log lines plus CPU, RAM, network and block I/O. Resource samples use the API's GraphQL WebSocket subscription; authentication uses the documented connection parameters. The socket exists only while the diagnostics sheet is active, closes on cancellation, and has bounded reconnect attempts and receive timeouts. Logs and metrics fail independently. Parity status, progress, error count, and speed appear on the server screen when supported. Detailed disk inventory continues to include cache, parity, and boot devices.
5. **VM completion verification.** Service-level resource coordination rejects duplicate commands across callers. Accepted VM mutations are followed by uncached expected-state checks, with a bounded verification window. Reboot observation runs during and after the mutation and requires a non-running-to-running transition; an unchanged running sample is insufficient. If completion cannot be observed, the UI says the command was accepted but unverified. Mutations are never automatically retried after ambiguous transport failures.

### Verification

The regression suite covers query size and resolver independence, different cache clocks/coalescing, stale data and Retry-After, endpoint/key changes during in-flight work, read-only/custom permissions, nullable inventory/large metrics, bounded logs and parity, duplicate VM commands, observed and unobserved VM transitions, and subscription authentication/filtering/ping/cancellation. Existing Docker command/fallback/error regression coverage is retained.

The offline simulator fixture is DEBUG-only and uses synthetic credentials and an `.invalid` hostname. UI coverage exercises partial VM failure with healthy containers, the logs/metrics sheet, read-only controls, and a six-second command that keeps its busy state past the former two-second timer. Screenshots are inspected for section availability and diagnostics layout.

- All 18 targeted tests passed on a fresh iPhone 17 / iOS 26.5 simulator: 16 service regressions and two UI tests. Final result bundle: `Test-Media Manager-2026.09.14_06-24-57--0400.xcresult`.
- Final iOS Debug test build and tvOS Debug simulator build passed.
- All 30 project plist/entitlement files passed validation; `git diff --check` passed.
- Final iOS Release simulator build passed; the resulting executable excludes the offline fixture hostname and launch flag. Built iOS/tvOS bundles report version 3.0 (16).

All 24 read/mutation/subscription shapes validate against both official API v4.36.0 and fetched current main schemas. Schema validation does not establish runtime authorization or daemon behavior.

Live Unraid Docker/VM execution, physical-device lifecycle behavior, and latency/battery measurements remain unverified. No live server commands or deployment were performed. The request-count tests establish cache behavior, not a measured battery or latency improvement.

Additional primary implementation references:

- [VM service and asynchronous operations](https://github.com/unraid/api/blob/main/api/src/unraid-api/graph/resolvers/vms/vms.service.ts)
- [WebSocket authentication guard](https://github.com/unraid/api/blob/main/api/src/unraid-api/auth/authentication.guard.ts)

### Follow-up correctness review

- Cache timestamps and backoff deadlines now begin when responses arrive, so slow requests cannot consume their own freshness window or Retry-After delay. Valid cached sections remain usable during server throttling; overlapping rate-limit responses preserve the longest outstanding cooldown.
- VM verification stops on HTTP 429 and shares the cooldown with the following status refresh. A paused, idle, suspended, crashed, or unknown sample cannot establish a reboot; verification requires an observed shutdown/stopped state followed by running.
- Refreshing failed hardware no longer replaces other healthy sections with the full-screen connection spinner. Changing the endpoint/key closes any open container diagnostics sheet.
- WebSocket partial-response errors are decoded before metrics data, preserving the server's permission/error message when the sample is null.

Added regressions cover response-time cache deadlines, overlapping cooldowns, rate-limited VM verification and follow-up reads, non-reboot state transitions, null metrics with GraphQL errors, and partial-section visibility during a delayed hardware refresh.

Follow-up validation: all 23 targeted checks passed (20 service tests and three UI tests) on iPhone 17 / iOS 26.5. Result bundle: `Test-Media Manager-2026.09.14_06-43-28--0400.xcresult`. The final iOS Debug test build, tvOS Debug build, and diff whitespace check passed. An earlier run failed to launch because the simulator was busy; after a full simulator boot the complete suite passed. Live-server validation remains outstanding.

### Dashboard behavior away from LAN

Server Health now hides its entire header and card for connectivity failures, including offline, DNS, connection loss/refusal, and timeout errors. The decision uses typed transport errors and also hides previously cached values while unreachable. Its lifecycle-bound polling continues while hidden; a foreground return bypasses ordinary read backoff to check again. Configuration/permission failures remain distinguishable from being away from the network. Regression coverage checks offline and recovered snapshots and dashboard visibility for unreachable versus reachable servers.


### Storage and cache warnings (September 15, 2026)

- Inventory reads now include `fsSize` and `fsFree` alongside `fsUsed`, all documented as KB in the [official schema](https://github.com/unraid/api/blob/main/api/generated-schema.graphql). Filesystem totals remain separate from physical device sizes; absent, negative, inconsistent, or overflowing values are unavailable rather than inferred as free space.
- Array capacity, individual data disks, and cache filesystems show usage bars and used/free space. Cache entries retain their server-reported identities and are never summed, because multiple devices can report the same pool filesystem. The overview's array capacity excludes cache capacity.
- The Unraid settings screen offers a local warning threshold of 5/10/15/20/25 percent free or Off, defaulting to 10. Critical warnings start at 5 percent free. The dashboard also surfaces low array space. These are in-app warnings, not background notifications.
- Failed reads retain labelled last-known capacity without generating fresh warnings; stopped arrays suppress capacity warnings. Existing away-from-LAN dashboard hiding remains in place.
- The current SABnzbd models do not establish a download-directory-to-Unraid-filesystem mapping. Queue size is therefore not compared against an assumed destination.
- Regression coverage exercises threshold boundaries, disabled/stale warnings, invalid values and overflow, physical-versus-filesystem size, missing cache readings, and array/cache separation. A simulator fixture exercises low array space, critical cache space, and unavailable cache usage.

Validation: 20 Unraid service tests passed, including the two storage regressions. The storage UI test passed on iPhone 17 Pro / iOS 26.5 after correcting its decimal-versus-binary formatting expectation; a separate simulator Busy launch failure was resolved by completing a fresh boot. iOS Debug test build and tvOS Debug simulator build passed. Storage/cache and disk-grid screenshots were inspected. Final UI result: `/tmp/media-storage-visual.xcresult`; service results: `/tmp/media-storage-tests.xcresult` (its original UI assertion failure was fixed and verified in the later UI run). Live-server capacity readings remain unverified.
