#!/usr/bin/env bash
set -euo pipefail

# Runs one non-overlapping XCTest category on an explicit simulator geometry.
#
# Usage:
#   ./scripts/run-ios-test-category.sh unit "iPhone 17" 26.2
#   ./scripts/run-ios-test-category.sh ui "iPhone SE (3rd generation)" 26.2
#   ./scripts/run-ios-test-category.sh snapshots "iPhone 16e" 26.2
#
# CI builds the test bundle once, then sets QUIZICE_TEST_ACTION to
# test-without-building for every visible category step.

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

readonly CATEGORY="${1:-}"
readonly DEVICE_NAME="${2:-}"
readonly RUNTIME_VERSION="${3:-26.2}"
readonly PROJECT="Quizice.xcodeproj"
readonly SCHEME="Quizice"
readonly CONFIGURATION="Debug"
readonly TEST_ACTION="${QUIZICE_TEST_ACTION:-test}"
readonly DERIVED_DATA_PATH="${QUIZICE_DERIVED_DATA_PATH:-DerivedData/CI}"
readonly RESULT_BUNDLE_PATH="${QUIZICE_RESULT_BUNDLE_PATH:-$DERIVED_DATA_PATH/TestResults/${CATEGORY}.xcresult}"
readonly TEST_LOG_PATH="${RESULT_BUNDLE_PATH%.xcresult}.log"

fail() {
  printf '❌ %s\n' "$*" >&2
  exit 1
}

case "$CATEGORY" in
  unit|ui|snapshots) ;;
  *) fail "category must be one of: unit, ui, snapshots" ;;
esac
[[ -n "$DEVICE_NAME" ]] || fail "simulator device name is required"
case "$TEST_ACTION" in
  test|test-without-building) ;;
  *) fail "QUIZICE_TEST_ACTION must be test or test-without-building" ;;
esac
[[ ! -e "$RESULT_BUNDLE_PATH" ]] || fail "result bundle already exists: $RESULT_BUNDLE_PATH"

mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")" "$DERIVED_DATA_PATH"

TEMP_FILES=()
CREATED_SIMULATOR_UDID=""
BOOTED_SIMULATOR_UDID=""
SIMULATOR_UDID=""
SIMULATOR_INITIAL_STATE=""

remember_temp_file() {
  TEMP_FILES+=("$1")
}

cleanup() {
  local path
  for path in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do
    [[ -n "$path" && -f "$path" ]] && rm -f "$path"
  done
  if [[ -n "$CREATED_SIMULATOR_UDID" ]]; then
    xcrun simctl shutdown "$CREATED_SIMULATOR_UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$CREATED_SIMULATOR_UDID" >/dev/null 2>&1 || true
  elif [[ -n "$BOOTED_SIMULATOR_UDID" ]]; then
    # Release devices we started while preserving simulators already in use.
    xcrun simctl shutdown "$BOOTED_SIMULATOR_UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

select_or_create_simulator() {
  local metadata_file
  metadata_file="$(mktemp -t quizice-simulators.XXXXXX.json)"
  remember_temp_file "$metadata_file"
  xcrun simctl list -j > "$metadata_file"

  local selection
  selection="$(python3 - "$metadata_file" "$DEVICE_NAME" "$RUNTIME_VERSION" <<'PY'
import json
import sys

metadata_path, requested_device_name, requested_runtime_version = sys.argv[1:4]
with open(metadata_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

runtime = next(
    (
        item for item in payload.get("runtimes", [])
        if item.get("version") == requested_runtime_version
        and item.get("isAvailable", True)
        and ".iOS-" in item.get("identifier", "")
    ),
    None,
)
if runtime is None:
    raise SystemExit(f"iOS {requested_runtime_version} runtime is unavailable")

device_type = next(
    (item for item in payload.get("devicetypes", []) if item.get("name") == requested_device_name),
    None,
)
if device_type is None:
    raise SystemExit(f"simulator device type is unavailable: {requested_device_name}")

candidates = []
for device in payload.get("devices", {}).get(runtime["identifier"], []):
    if not device.get("isAvailable", True):
        continue
    if device.get("deviceTypeIdentifier") != device_type.get("identifier"):
        continue
    state = device.get("state", "")
    candidates.append((0 if state == "Booted" else 1, device.get("name", ""), device["udid"], state))

selected = sorted(candidates)[0] if candidates else None
udid, initial_state = selected[2:] if selected else ("", "")
print("|".join((udid, device_type["identifier"], runtime["identifier"], initial_state)))
PY
)" || fail "could not resolve $DEVICE_NAME on iOS $RUNTIME_VERSION"

  local device_type_identifier
  local runtime_identifier
  IFS='|' read -r SIMULATOR_UDID device_type_identifier runtime_identifier SIMULATOR_INITIAL_STATE <<< "$selection"
  if [[ -z "$SIMULATOR_UDID" ]]; then
    SIMULATOR_UDID="$(xcrun simctl create \
      "Quizice CI - $DEVICE_NAME - iOS $RUNTIME_VERSION" \
      "$device_type_identifier" \
      "$runtime_identifier")"
    CREATED_SIMULATOR_UDID="$SIMULATOR_UDID"
    SIMULATOR_INITIAL_STATE="Shutdown"
    printf 'Created simulator: %s (%s, iOS %s)\n' "$SIMULATOR_UDID" "$DEVICE_NAME" "$RUNTIME_VERSION" >&2
  fi
}

collect_snapshot_sources() {
  find QuiziceTests/Snapshots \
    -maxdepth 1 \
    -type f \
    -name '*Tests.swift' \
    -print
}

collect_ui_sources() {
  find QuiziceTests/Features/Home/Tests \
    -maxdepth 1 \
    -type f \
    -name '*Tests.swift' \
    -print
  find QuiziceTests/Features \
    -type f \
    -path '*/UIContracts/*Tests.swift' \
    -print
}

append_test_suite_names() {
  local source_list="$1"
  local output="$2"
  local source_file
  while IFS= read -r source_file; do
    [[ -n "$source_file" ]] || continue
    sed -nE \
      's/^[[:space:]]*(final[[:space:]]+)?class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*Tests)[[:space:]]*:.*/\2/p' \
      "$source_file" >> "$output"
  done < "$source_list"
}

count_test_methods() {
  local source_list="$1"
  local count=0
  local source_file
  local source_count
  while IFS= read -r source_file; do
    [[ -n "$source_file" ]] || continue
    source_count="$(grep -Ec '^[[:space:]]*func[[:space:]]+test[A-Za-z0-9_]*[[:space:]]*\(' "$source_file" || true)"
    count=$((count + source_count))
  done < "$source_list"
  printf '%s\n' "$count"
}

readonly SNAPSHOT_SOURCES="$(mktemp -t quizice-snapshot-sources.XXXXXX.list)"
readonly UI_SOURCES="$(mktemp -t quizice-ui-sources.XXXXXX.list)"
readonly EXCLUDED_SOURCES="$(mktemp -t quizice-excluded-sources.XXXXXX.list)"
readonly CATEGORY_SUITES="$(mktemp -t quizice-category-suites.XXXXXX.list)"
readonly ALL_TEST_SOURCES="$(mktemp -t quizice-all-test-sources.XXXXXX.list)"
remember_temp_file "$SNAPSHOT_SOURCES"
remember_temp_file "$UI_SOURCES"
remember_temp_file "$EXCLUDED_SOURCES"
remember_temp_file "$CATEGORY_SUITES"
remember_temp_file "$ALL_TEST_SOURCES"

collect_snapshot_sources | LC_ALL=C sort -u > "$SNAPSHOT_SOURCES"
collect_ui_sources | LC_ALL=C sort -u > "$UI_SOURCES"
{
  cat "$SNAPSHOT_SOURCES"
  cat "$UI_SOURCES"
} | LC_ALL=C sort -u > "$EXCLUDED_SOURCES"
find QuiziceTests -type f -name '*.swift' -print | LC_ALL=C sort -u > "$ALL_TEST_SOURCES"

FILTER_ARGUMENTS=()
EXPECTED_TEST_COUNT=0

case "$CATEGORY" in
  snapshots)
    append_test_suite_names "$SNAPSHOT_SOURCES" "$CATEGORY_SUITES"
    EXPECTED_TEST_COUNT="$(count_test_methods "$SNAPSHOT_SOURCES")"
    ;;
  ui)
    append_test_suite_names "$UI_SOURCES" "$CATEGORY_SUITES"
    EXPECTED_TEST_COUNT="$(count_test_methods "$UI_SOURCES")"
    ;;
  unit)
    append_test_suite_names "$EXCLUDED_SOURCES" "$CATEGORY_SUITES"
    readonly ALL_TEST_COUNT="$(count_test_methods "$ALL_TEST_SOURCES")"
    readonly EXCLUDED_TEST_COUNT="$(count_test_methods "$EXCLUDED_SOURCES")"
    EXPECTED_TEST_COUNT=$((ALL_TEST_COUNT - EXCLUDED_TEST_COUNT))
    ;;
esac

LC_ALL=C sort -u "$CATEGORY_SUITES" -o "$CATEGORY_SUITES"
[[ -s "$CATEGORY_SUITES" ]] || fail "no XCTest suites found for category: $CATEGORY"
(( EXPECTED_TEST_COUNT > 0 )) || fail "no XCTest methods found for category: $CATEGORY"

while IFS= read -r suite_name; do
  [[ -n "$suite_name" ]] || continue
  if [[ "$CATEGORY" == "unit" ]]; then
    FILTER_ARGUMENTS+=("-skip-testing:QuiziceTests/$suite_name")
  else
    FILTER_ARGUMENTS+=("-only-testing:QuiziceTests/$suite_name")
  fi
done < "$CATEGORY_SUITES"

select_or_create_simulator
[[ -n "$SIMULATOR_UDID" ]] || fail "simulator selection returned an empty UDID"
printf 'Preparing simulator: %s (%s, initial state: %s)\n' \
  "$SIMULATOR_UDID" "$DEVICE_NAME" "$SIMULATOR_INITIAL_STATE"
if xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1; then
  if [[ "$SIMULATOR_INITIAL_STATE" == "Shutdown" ]]; then
    BOOTED_SIMULATOR_UDID="$SIMULATOR_UDID"
  fi
fi
xcrun simctl bootstatus "$SIMULATOR_UDID" -b

if [[ "$CATEGORY" == "snapshots" ]]; then
  for key in QUIZICE_RECORD_SNAPSHOTS SNAPSHOT_TESTING_RECORD; do
    [[ -z "${!key:-}" ]] || fail "$key must be unset for snapshot verification"
    [[ -z "$(xcrun simctl spawn "$SIMULATOR_UDID" launchctl getenv "$key" 2>/dev/null || true)" ]] || \
      fail "$key is set in the selected simulator"
  done
fi

printf '\nRunning %s tests (%s expected) on %s, iOS %s...\n' \
  "$CATEGORY" "$EXPECTED_TEST_COUNT" "$DEVICE_NAME" "$RUNTIME_VERSION"

XCODEBUILD_ARGUMENTS=(
  -quiet
  -skipPackagePluginValidation
  -skipMacroValidation
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGNING_ALLOWED=NO
  -parallel-testing-enabled NO
  -enableCodeCoverage YES
  -resultBundlePath "$RESULT_BUNDLE_PATH"
)
XCODEBUILD_ARGUMENTS+=("${FILTER_ARGUMENTS[@]}")
XCODEBUILD_ARGUMENTS+=("$TEST_ACTION")

set +e
xcodebuild "${XCODEBUILD_ARGUMENTS[@]}" 2>&1 | tee "$TEST_LOG_PATH"
XCODEBUILD_STATUS="${PIPESTATUS[0]}"
set -e

if [[ ! -d "$RESULT_BUNDLE_PATH" ]]; then
  (( XCODEBUILD_STATUS == 0 )) || fail "xcodebuild failed before producing an xcresult"
  fail "xcodebuild did not produce the expected xcresult: $RESULT_BUNDLE_PATH"
fi

SUMMARY_JSON="$(mktemp -t quizice-test-summary.XXXXXX.json)"
remember_temp_file "$SUMMARY_JSON"
xcrun xcresulttool get test-results summary \
  --path "$RESULT_BUNDLE_PATH" \
  --compact > "$SUMMARY_JSON"

set +e
python3 - \
  "$SUMMARY_JSON" \
  "$CATEGORY" \
  "$DEVICE_NAME" \
  "$RUNTIME_VERSION" \
  "$EXPECTED_TEST_COUNT" \
  "${GITHUB_STEP_SUMMARY:-}" <<'PY'
import json
import sys

summary_path, category, device, runtime, expected, step_summary_path = sys.argv[1:7]
expected_count = int(expected)
with open(summary_path, "r", encoding="utf-8") as handle:
    summary = json.load(handle)

total = int(summary.get("totalTestCount", 0))
passed = int(summary.get("passedTests", 0))
failed = int(summary.get("failedTests", 0))
skipped = int(summary.get("skippedTests", 0))
print(f"{category}: {total} executed, {passed} passed, {failed} failed, {skipped} skipped")

if step_summary_path:
    with open(step_summary_path, "a", encoding="utf-8") as handle:
        handle.write(f"### {category.title()} tests — {device}\n\n")
        handle.write(f"iOS {runtime}: **{passed} passed**, {failed} failed, {skipped} skipped ({total} total).\n\n")

for failure in summary.get("testFailures", []):
    test_name = failure.get("testName") or failure.get("testIdentifierString") or "unknown test"
    message = " ".join((failure.get("failureText") or "No failure message").split())
    print(f"- {test_name}: {message}", file=sys.stderr)

if total != expected_count:
    print(
        f"expected {expected_count} {category} tests, but xcresult reports {total}; "
        "the CI category filters are incomplete",
        file=sys.stderr,
    )
    raise SystemExit(2)
PY
SUMMARY_STATUS="$?"
set -e

if (( XCODEBUILD_STATUS != 0 )); then
  fail "xcodebuild $CATEGORY tests failed (xcresult: $RESULT_BUNDLE_PATH)"
fi
if (( SUMMARY_STATUS != 0 )); then
  fail "xcresult test-count validation failed for $CATEGORY"
fi

COVERAGE_JSON="$(mktemp -t quizice-category-coverage.XXXXXX.json)"
remember_temp_file "$COVERAGE_JSON"
xcrun xccov view --report --json "$RESULT_BUNDLE_PATH" > "$COVERAGE_JSON"
python3 - "$COVERAGE_JSON" "$CATEGORY" "${GITHUB_STEP_SUMMARY:-}" <<'PY'
import json
import sys

coverage_path, category, step_summary_path = sys.argv[1:4]
with open(coverage_path, "r", encoding="utf-8") as handle:
    report = json.load(handle)

targets = [
    target for target in report.get("targets", [])
    if target.get("name") in {"Quizice", "Quizice.app"}
    or (target.get("name", "").startswith("Quizice") and "Tests" not in target.get("name", ""))
]
if not targets:
    raise SystemExit("Quizice app target is missing from the coverage report")
target = max(targets, key=lambda item: item.get("executableLines", 0))
percent = float(target.get("lineCoverage", 0)) * 100
print(f"{category} app line coverage: {percent:.2f}%")
if step_summary_path:
    with open(step_summary_path, "a", encoding="utf-8") as handle:
        handle.write(f"Category app line coverage: **{percent:.2f}%**.\n\n")
PY

printf '✅ %s tests passed on %s (iOS %s).\n' "$CATEGORY" "$DEVICE_NAME" "$RUNTIME_VERSION"
printf 'xcresult: %s\n' "$RESULT_BUNDLE_PATH"
