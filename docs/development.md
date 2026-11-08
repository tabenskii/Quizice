# Development guide

[Back to README](../README.md)

Start with [Build from source](../README.md#build-from-source) for a local Debug
build. This guide covers optional services, production configuration and checks.
Run all commands from the repository root.

## Build secrets

Credentials that must not appear in source control live in
`Configurations/Secrets.xcconfig`, which is git-ignored. Copy the template on
first checkout:

```bash
cp -n Configurations/Secrets.xcconfig.template Configurations/Secrets.xcconfig
# then fill in APPMETRICA_API_KEY and BACKEND_BASE_URL
```

Debug builds allow both variables to be empty: analytics stays disabled and a
fresh installation uses bundled catalog data. Release builds require `BACKEND_BASE_URL`
to be an HTTPS backend URL ending in `/api`, without credentials, query or
fragment. A build phase rejects missing, malformed and local backend addresses;
it does not contact the server. `APPMETRICA_API_KEY` remains optional.
In an xcconfig file, write the URL as `https:/$()/backend.example.com/api` so
the double slash is not parsed as a comment.

`Configurations/Shared.xcconfig` is the base configuration for the app target
and pulls in `Secrets.xcconfig` via an optional include; the project's build
settings no longer carry those values directly.

## Yandex AppMetrica

The app uses AppMetrica 6.4.0 for product analytics, sessions, crashes, and
sanitized operational errors. Advertising attribution, IDFA, location, user
profiles, and automatic revenue tracking are disabled.

1. Register the iOS app in AppMetrica and copy its API key from
   **Settings → Main**.
2. Paste the value into `APPMETRICA_API_KEY` in
   `Configurations/Secrets.xcconfig` (see **Build secrets** above).
3. Keep the same value for Debug and Release so local sessions and production
   sessions reach the same app.

The value is substituted into the `AppMetricaAPIKey` entry in `Info.plist`.
An empty value or the placeholder leaves analytics disabled. XCTest and SwiftUI
Previews also skip SDK activation.

AppMetrica's verbose internal logging is disabled by default, including in
Debug builds. To troubleshoot the SDK itself, set the
`QUIZICE_APPMETRICA_VERBOSE_LOGS` environment variable to `1` in the Run scheme.
Normal Debug runs keep only Quizice's compact per-event log.

Events cover screen views, theme selection, quiz start/answers/timeouts/exit/
completion, result actions, statistics, AI generation, and settings changes.
Question text, answer text, AI prompts, localized error messages, and generated
AI theme IDs are never sent to analytics. The backend separately receives the
authenticated user ID, quiz progress and selected answers, and the AI prompt
when the user requests a generated quiz, to provide those features.

AppMetrica 6.4.0 provides its own Privacy Manifest. App Store Connect privacy
answers should still declare the diagnostics and other analytics data collected
by the SDK, as well as the linked user ID, gameplay content and other user
content sent to the backend for app functionality. The bundled privacy manifest
declares these backend data categories; App Store Connect privacy answers and
the published privacy policy need to be reviewed separately before release.
Because `AppMetricaAdSupport` is not linked, the app does not use
AppMetrica cross-app tracking and does not request ATT permission.

## Production backend

The app reads `BackendBaseURL` from the `BACKEND_BASE_URL` build setting,
which comes from `Configurations/Secrets.xcconfig` (see **Build secrets**).
Configured Debug and Release builds use the deployed HTTPS API. Debug can also
opt into `http://localhost:8000/api` from the developer menu, opened by holding
the Home settings button for 0.5 seconds. Backend changes require a restart.
On a physical iPhone, `localhost` refers to the phone itself.

The client initially loads a matching cached backend catalog or bundled localized
data, then refreshes theme metadata during launch preparation. In backend catalog
mode, starting a quiz requests a seeded question batch and requires a valid
response; a failed request does not fall back to bundled questions. Cached
backend metadata alone does not make quizzes available offline. See the
[app reference](app-reference.md#каталог-и-offline) for the exact loading rules.

Release AI generation goes through the backend. It requires a valid backend
session obtained through Game Center. The token is stored in Keychain and sent
using the backend authentication header (`X-Quizice-Authorization`). Debug
Simulator uses the direct AI service; Debug on a device can opt into it with a
local key (see [Debug differences](app-reference.md#отличия-debug)).
Production provider credentials remain server-side. The required server
contract, rollout order, tests, and performance targets are documented in
[`docs/backend-production-readiness-plan.md`](backend-production-readiness-plan.md).

`LiveBackendContractTests` are opt-in so ordinary unit-test runs never depend on
the network. Set `QUIZICE_RUN_LIVE_BACKEND_TESTS=1` in the test scheme to run
them. The latency smoke reports first/median/p95/max timings without using an
unstable developer connection as a release threshold. Set `QUIZICE_LIVE_BACKEND_URL`
to an alternate API base URL ending in `/api`; health and readiness then use
that same origin. Invalid overrides fail instead of falling back to production.
The two `testFuture...` cases are rollout gates for the new response envelopes
and guest AI `401`.

CI also compiles Release with a reserved, non-routable example backend URL to
exercise the production build path without service credentials or network probes.
Validate the configuration gate locally with
`python3 scripts/tests/test-release-configuration.py`.

## SwiftLint

SwiftLint is integrated as an SPM build-tool plugin for both `Quizice` and
`QuiziceTests`. The shared rules live in `.swiftlint.yml` and run automatically
when either target is built. On first use, Xcode may ask you to trust and enable
the `SwiftLintBuildToolPlugin`.

## Running tests

CI uses Xcode 26.2 and the iOS 26.2 Simulator runtime. Install that runtime before
running the documented XCTest commands; snapshot baselines use iPhone 16e on
iOS 26.2. The category runner selects or creates a matching simulator.

```sh
# Static contracts and configuration regressions; no simulator needed.
./scripts/verify-s04-tests-and-failure-states.sh --checks-only
python3 scripts/tests/test-release-configuration.py
python3 scripts/tests/test-static-verifier.py

# Unit, UI contract, and snapshot categories.
./scripts/run-ios-test-category.sh unit "iPhone 17" 26.2
./scripts/run-ios-test-category.sh ui "iPhone SE (3rd generation)" 26.2
./scripts/run-ios-test-category.sh snapshots "iPhone 16e" 26.2
```

By default, the runner writes to `DerivedData/CI/TestResults/<category>.xcresult`
and refuses to overwrite an existing bundle. For a rerun, set a new result path:

```sh
QUIZICE_RESULT_BUNDLE_PATH=DerivedData/CI/TestResults/unit-rerun.xcresult \
  ./scripts/run-ios-test-category.sh unit "iPhone 17" 26.2
```

Set `QUIZICE_RECORD_SNAPSHOTS=1` only when intentionally updating the visual
baselines. Inspect the changed PNGs, then rerun without recording and with a
fresh result-bundle path.

The [CI workflow](../.github/workflows/ios-tests.yml) builds for testing once,
runs each category with `test-without-building`, adds UI contracts on iPhone 17
Pro Max, and combines coverage with
[`merge-ios-test-results.sh`](../scripts/merge-ios-test-results.sh).

For a local Release compile without service credentials, use the same reserved
example URL as CI. This validates configuration and compilation; it does not
test a running backend or produce a signed distribution build.

```sh
xcodebuild \
  -project Quizice.xcodeproj \
  -scheme Quizice \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData/Release \
  CODE_SIGNING_ALLOWED=NO \
  'BACKEND_BASE_URL=https://release-config.example.invalid/api' \
  APPMETRICA_API_KEY= \
  build
```

## Further reading

- [App reference](app-reference.md) — detailed behavior and API contracts (Russian).
- [Architecture review](architecture-review.md) and [refactor report](refactor-report.md).
- [SwiftUI migration assessment](swiftui-migration-assessment.md).
- [Backend production readiness plan](backend-production-readiness-plan.md) —
  server contract and rollout requirements; a plan is not a live service status.


## Renewable simulator test account

Debug Simulator builds support a private backend test account with automatic session renewal. In the debug menu (long-press Settings), use **Connect / renew test account**. Enter the private test-account key once; later, leave the field empty to use the saved key. Successful connection immediately rebuilds the app flow with the backend account. The key and bearer session are stored in device-only Keychain and scoped to the backend URL. Neither belongs in source, build settings, Info.plist, logs, screenshots, or PRs.

The backend's optional `/api/v1/auth/test-account` endpoint binds this key to one server-selected `dev:<UUID>` account; it cannot select or impersonate a Game Center user. Bearer sessions last 30 days by default. On launch, the client renews sessions with less than one day remaining, including expired sessions. A still-valid session remains usable during transient renewal outages. Server rejection clears the cached session; renewal is bounded and does not create an authentication loop. The private key is administratively revocable and does not expire monthly. Account statistics and normal AI quotas are preserved.

For automated setup, supply `QUIZICE_TEST_ACCOUNT_KEY` through the launching process environment for one simulator launch (`SIMCTL_CHILD_QUIZICE_TEST_ACCOUNT_KEY` with simctl). Do not put it in command-line arguments. The backend configuration and key must already be enabled by the administrator. The key is redacted from the Pulse network logger. The menu/import/provider selection are limited to Debug Simulator builds; `QUIZICE_REQUIRE_GAME_CENTER=1` explicitly selects Game Center instead.

The older one-time `QUIZICE_DEBUG_SESSION_BASE64` import remains supported for existing installations. It accepts base64 JSON with this shape (all values are examples):

```json
{"backendBaseURL":"https://backend.example/api","session":{"userID":"550e8400-e29b-41d4-a716-446655440001","teamPlayerID":"dev:550e8400-e29b-41d4-a716-446655440000","accessToken":"REPLACE_WITH_SERVER_ISSUED_TOKEN","expiresAt":"2099-01-01T00:00:00Z"}}
```

That legacy session cannot renew without a private test-account key. Existing explicit `DEV_AUTH_ENABLED` / `DEV_AUTH_SECRET` staging authentication is unchanged; production `/auth/dev` stays disabled.

When building from a worktree, privately copy the ignored `Configurations/Secrets.xcconfig` into the worktree. Without `BACKEND_BASE_URL`, the app cannot reach the backend. Use normal ad-hoc Simulator signing; disabling signing prevents Keychain access.
