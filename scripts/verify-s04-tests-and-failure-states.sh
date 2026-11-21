#!/usr/bin/env bash
set -euo pipefail

# S04 test infrastructure and safe local failure-states verifier.
#
# Scope rules:
# - delegates upstream S03 contract verification first;
# - runs the repository-local app build before tests;
# - selects an available iOS Simulator deterministically for xcodebuild test;
# - verifies the Quizice scheme discovers and executes the QuiziceTests suite;
# - verifies the R007/R008 XCTest coverage markers remain present;
# - verifies Point-Free SnapshotTesting is linked through the QuiziceTests target;
# - runs tests with code coverage and enforces a risk-based minimum app line coverage;
# - preserves Quizice/data.json and never uses it as a mutable fixture;
# - keeps failures loud and actionable for local developer/CI-style invocation.
#
# To intentionally refresh image snapshots locally, run the XCTest command below
# with QUIZICE_RECORD_SNAPSHOTS=1, inspect the changed PNGs, then rerun this
# verifier without recording.

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

readonly VERIFIER_MODE="${1:-full}"
case "$VERIFIER_MODE" in
  full|--checks-only) ;;
  *)
    printf 'Usage: %s [--checks-only]\n' "$0" >&2
    exit 64
    ;;
esac

# Static mode must also keep delegated S01-S03 checks and package discovery
# offline. The separate build/test steps validate Xcode integration.
if [[ "$VERIFIER_MODE" == "--checks-only" ]]; then
  export QUIZICE_SKIP_XCODEBUILD=1
fi

readonly S03_VERIFIER="./scripts/verify-s03-statistics-screen-contracts.sh"
readonly PROJECT="Quizice.xcodeproj"
readonly PROJECT_FILE="$PROJECT/project.pbxproj"
readonly SCHEME="Quizice"
readonly CONFIGURATION="Debug"
readonly DATA_JSON="Quizice/data.json"
readonly SMOKE_TESTS="QuiziceTests/Unit/QuiziceTests.swift"
readonly SUMMARY_TESTS="QuiziceTests/Unit/StatisticsSummaryTests.swift"
readonly STORE_TESTS="QuiziceTests/Unit/StatisticsStoreTests.swift"
readonly PRESENTER_FAILURE_TESTS="QuiziceTests/Unit/QuizQuestionPresenterFailureStateTests.swift"
readonly SNAPSHOT_SUPPORT_TESTS="QuiziceTests/Snapshots/SnapshotSupport.swift"
readonly COMPONENT_SNAPSHOT_TESTS="QuiziceTests/Snapshots/ComponentSnapshotTests.swift"
readonly HOME_CARD_SNAPSHOT_TESTS="QuiziceTests/Snapshots/HomeCardSnapshotTests.swift"
readonly HOME_COLLECTION_TESTS="QuiziceTests/Features/Home/Tests/HomeCollectionServiceTests.swift"
readonly SCREEN_SNAPSHOT_TESTS="QuiziceTests/Snapshots/ScreenSnapshotTests.swift"
readonly SWIFTUI_SNAPSHOT_TESTS="QuiziceTests/Snapshots/SwiftUISnapshotTests.swift"
readonly APP_APPEARANCE_TESTS="QuiziceTests/Unit/AppAppearanceTests.swift"
readonly QUESTION_PRESENTER_TESTS="QuiziceTests/Unit/QuizQuestionPresenterTests.swift"
readonly QUIZ_FACTORY_TESTS="QuiziceTests/Unit/QuizFactoryTests.swift"
readonly AI_WORKFLOW="Quizice/Features/Home/Presentation/QuizViewController+AIWorkflow.swift"
readonly QUIZ_FLOW_COORDINATOR="Quizice/App/Navigation/QuizFlowCoordinator.swift"
readonly RETIRED_DESCRIPTION_VIEW_CONTROLLER="Quizice/Features/QuizDescription/UI/QuizDescriptionViewController.swift"
readonly SNAPSHOT_RUNTIME_IDENTIFIER="com.apple.CoreSimulator.SimRuntime.iOS-26-2"
readonly SNAPSHOT_HOST_DEVICE_TYPE_SUFFIX=".iPhone-16e"
readonly MIN_LINE_COVERAGE_PERCENT=80
readonly MAX_SWIFT_FILE_LINES=700
# Keep the global limit meaningful while ratcheting down two pre-existing
# oversized production files. These ceilings may only move downward as the
# files are split; new files never inherit an exception.
readonly -a LEGACY_SWIFT_FILE_LINE_LIMITS=(
  "Quizice/Features/Home/Collection/ThemesCollectionService.swift|741"
  "Quizice/Features/Settings/UI/QuizSettingsView.swift|741"
)
# The previous split set exposed 203 methods. Retiring nine standalone
# Description/Statistics controller tests leave 194 preserved split tests; the
# inline large-history layout regression raises the retained floor to 195.
readonly MIN_SPLIT_TEST_METHODS=195

readonly -a REMOVED_TEST_FILES=(
  "QuiziceTests/UI/HomeScreenVisualStateTests.swift"
  "QuiziceTests/UI/CrossScreenVisualStateTests.swift"
  "QuiziceTests/Unit/HomeThemeCardFeatureTests.swift"
  "QuiziceTests/Unit/QuizFlowCoordinatorAdditionalTests.swift"
  "QuiziceTests/Unit/YandexAIQuizThemeServiceTests.swift"
  "QuiziceTests/Unit/QuizPresenterTests.swift"
  "QuiziceTests/Features/QuizDescription/UIContracts/QuizDescriptionViewContractTests.swift"
  "QuiziceTests/Features/Statistics/UIContracts/StatisticsViewContractTests.swift"
)

readonly -a SPLIT_TEST_SOURCE_FILES=(
  "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizContractValidationTests.swift"
  "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeErrorTests.swift"
  "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeRequestTests.swift"
  "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeResponseTests.swift"
  "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeTransportTests.swift"
  "QuiziceTests/Features/AppFlow/UIContracts/CrossScreenAccessibilityContractTests.swift"
  "QuiziceTests/Features/AppFlow/Unit/QuizFlowCoordinatorAIThemeTests.swift"
  "QuiziceTests/Features/AppFlow/Unit/QuizFlowCoordinatorLaunchTests.swift"
  "QuiziceTests/Features/AppFlow/Unit/QuizFlowCoordinatorNavigationTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeAIThemeCardInteractionTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeAIThemeCardTransitionTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeCollectionServicePresentationTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeCollectionServiceTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeExpandedCardTransitionTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeExpandedThemeCardInteractionTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeExpandedThemeCardMotionTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeFeelingLuckyTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeScreenLayoutTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeScreenVisualStateTestSupport.swift"
  "QuiziceTests/Features/Home/Tests/HomeSettingsVisualStateTests.swift"
  "QuiziceTests/Features/Home/Tests/HomeThemeCardStateTests.swift"
  "QuiziceTests/Features/Home/Tests/MockAIQuizThemeServiceHomeTests.swift"
  "QuiziceTests/Features/Home/Unit/HomeAIThemeCardReducerTests.swift"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardParallaxTests.swift"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardReducerTests.swift"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardTransitionTests.swift"
  "QuiziceTests/Features/Home/Unit/QuizQuestionCountPolicyTests.swift"
  "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionStateContractTests.swift"
  "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionTypographyContractTests.swift"
  "QuiziceTests/Features/QuizResult/UIContracts/QuizResultViewContractTests.swift"
  "QuiziceTests/Features/Statistics/UIContracts/StatisticsCardCollectionViewCellTests.swift"
  "QuiziceTests/Support/CrossScreenVisualTestCase.swift"
  "QuiziceTests/Support/QuizFlowCoordinatorTestCase.swift"
  "QuiziceTests/Support/UIView+TestDescendant.swift"
  "QuiziceTests/Support/YandexAIQuizThemeServiceTestCase.swift"
)

readonly -a SPLIT_TEST_SUITE_LAYOUT=(
  "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizContractValidationTests.swift|YandexAIQuizContractValidationTests"
  "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeErrorTests.swift|YandexAIQuizThemeErrorTests"
  "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeRequestTests.swift|YandexAIQuizThemeRequestTests"
  "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeResponseTests.swift|YandexAIQuizThemeResponseTests"
  "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeTransportTests.swift|YandexAIQuizThemeTransportTests"
  "QuiziceTests/Features/AppFlow/UIContracts/CrossScreenAccessibilityContractTests.swift|CrossScreenAccessibilityContractTests"
  "QuiziceTests/Features/AppFlow/Unit/QuizFlowCoordinatorAIThemeTests.swift|QuizFlowCoordinatorAIThemeTests"
  "QuiziceTests/Features/AppFlow/Unit/QuizFlowCoordinatorLaunchTests.swift|QuizFlowCoordinatorLaunchTests"
  "QuiziceTests/Features/AppFlow/Unit/QuizFlowCoordinatorNavigationTests.swift|QuizFlowCoordinatorNavigationTests"
  "QuiziceTests/Features/Home/Tests/HomeAIThemeCardInteractionTests.swift|HomeAIThemeCardInteractionTests"
  "QuiziceTests/Features/Home/Tests/HomeAIThemeCardTransitionTests.swift|HomeAIThemeCardTransitionTests"
  "QuiziceTests/Features/Home/Tests/HomeCollectionServicePresentationTests.swift|HomeCollectionServicePresentationTests"
  "QuiziceTests/Features/Home/Tests/HomeCollectionServiceTests.swift|HomeCollectionServiceTests"
  "QuiziceTests/Features/Home/Tests/HomeExpandedCardTransitionTests.swift|HomeExpandedCardTransitionTests"
  "QuiziceTests/Features/Home/Tests/HomeExpandedThemeCardInteractionTests.swift|HomeExpandedThemeCardInteractionTests"
  "QuiziceTests/Features/Home/Tests/HomeExpandedThemeCardMotionTests.swift|HomeExpandedThemeCardMotionTests"
  "QuiziceTests/Features/Home/Tests/HomeFeelingLuckyTests.swift|HomeFeelingLuckyTests"
  "QuiziceTests/Features/Home/Tests/HomeScreenLayoutTests.swift|HomeScreenLayoutTests"
  "QuiziceTests/Features/Home/Tests/HomeScreenVisualStateTestSupport.swift|HomeScreenVisualStateTestCase"
  "QuiziceTests/Features/Home/Tests/HomeSettingsVisualStateTests.swift|HomeSettingsVisualStateTests"
  "QuiziceTests/Features/Home/Tests/HomeThemeCardStateTests.swift|HomeThemeCardStateTests"
  "QuiziceTests/Features/Home/Tests/MockAIQuizThemeServiceHomeTests.swift|MockAIQuizThemeServiceHomeTests"
  "QuiziceTests/Features/Home/Unit/HomeAIThemeCardReducerTests.swift|HomeAIThemeCardReducerTests"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardParallaxTests.swift|HomeThemeCardExpansionParallaxStateTests"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardParallaxTests.swift|HomeThemeCardParallaxPresentationPhaseTests"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardParallaxTests.swift|HomeThemeCardParallaxInputTests"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardParallaxTests.swift|HomeThemeCardPanParallaxMapperTests"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardParallaxTests.swift|HomeThemeCardParallaxGesturePolicyTests"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardParallaxTests.swift|HomeThemeCardParallaxRenderStateTests"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardParallaxTests.swift|HomeThemeCardMotionInputMapperTests"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardReducerTests.swift|HomeThemeCardReducerTests"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardTransitionTests.swift|HomeThemeCardTransitionGeometryTests"
  "QuiziceTests/Features/Home/Unit/HomeThemeCardTransitionTests.swift|HomeThemeCardTransitionVisualStateTests"
  "QuiziceTests/Features/Home/Unit/QuizQuestionCountPolicyTests.swift|QuizQuestionCountPolicyTests"
  "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionStateContractTests.swift|QuizQuestionStateContractTests"
  "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionTypographyContractTests.swift|QuizQuestionTypographyContractTests"
  "QuiziceTests/Features/QuizResult/UIContracts/QuizResultViewContractTests.swift|QuizResultViewContractTests"
  "QuiziceTests/Features/Statistics/UIContracts/StatisticsCardCollectionViewCellTests.swift|StatisticsCardCollectionViewCellTests"
  "QuiziceTests/Support/CrossScreenVisualTestCase.swift|CrossScreenVisualTestCase"
  "QuiziceTests/Support/QuizFlowCoordinatorTestCase.swift|QuizFlowCoordinatorTestCase"
  "QuiziceTests/Support/YandexAIQuizThemeServiceTestCase.swift|YandexAIQuizThemeServiceTestCase"
)

TEMP_FILES=()
TEMP_PATHS=()
DATA_JSON_INITIAL_HASH=""

log_section() {
  printf '\n== %s ==\n' "$1"
}

fail() {
  printf '❌ S04 verifier failed: %s\n' "$1" >&2
  exit 1
}

print_xctest_failure_summary() {
  local result_bundle="$1"
  local test_log="$2"
  local summary_json
  summary_json="$(mktemp -t quizice-s04-xcresult-summary.XXXXXX.json)"
  remember_temp_file "$summary_json"

  log_section "XCTest failure summary" >&2

  if xcrun xcresulttool get test-results summary --path "$result_bundle" --compact > "$summary_json" 2>/dev/null; then
    if python3 - "$summary_json" "${GITHUB_ACTIONS:-}" "${GITHUB_STEP_SUMMARY:-}" "$PROJECT_ROOT" <<'PY'
import json
import re
import sys

summary_path, github_actions, step_summary_path, project_root = sys.argv[1:5]

with open(summary_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

failures = []

def walk(value):
    if isinstance(value, dict):
        if value.get("testName") or value.get("failureText"):
            failures.append(value)
        for child in value.values():
            walk(child)
    elif isinstance(value, list):
        for child in value:
            walk(child)

walk(payload.get("testFailures", payload))

deduplicated = []
seen = set()
for failure in failures:
    key = (
        failure.get("targetName", ""),
        failure.get("testName", ""),
        failure.get("failureText", ""),
    )
    if key not in seen:
        seen.add(key)
        deduplicated.append(failure)

def escape_github(value):
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")

def swift_location(text):
    match = re.search(r"((?:/[^:\n]+)?[^:\n]+\.swift):(\d+)", text)
    if match:
        return match.group(1), match.group(2)
    return "", ""

if not deduplicated:
    print("No structured XCTest failures were found in the xcresult summary.", file=sys.stderr)
    raise SystemExit(2)

summary_lines = [
    "### XCTest failure summary",
    "",
    "| Target | Test | Message |",
    "| --- | --- | --- |",
]

for index, failure in enumerate(deduplicated, start=1):
    target = failure.get("targetName") or "unknown target"
    test_name = failure.get("testName") or failure.get("testIdentifierString") or "unknown test"
    message = (failure.get("failureText") or "").strip() or "No failure message in xcresult."
    one_line_message = " ".join(message.split())
    print(f"{index}. {target} / {test_name}", file=sys.stderr)
    print(f"   {one_line_message}", file=sys.stderr)

    file_path, line = swift_location(message)
    if file_path.startswith(project_root + "/"):
        file_path = file_path[len(project_root) + 1:]
    if github_actions.lower() == "true":
        annotation = f"::error title={escape_github(test_name)}"
        if file_path:
            annotation += f",file={escape_github(file_path)}"
        if line:
            annotation += f",line={line}"
        annotation += f"::{escape_github(one_line_message)}"
        print(annotation)

    markdown_message = one_line_message.replace("|", "\\|")
    summary_lines.append(f"| `{target}` | `{test_name}` | {markdown_message} |")

if step_summary_path:
    with open(step_summary_path, "a", encoding="utf-8") as handle:
        handle.write("\n".join(summary_lines))
        handle.write("\n")
PY
    then
      return
    fi
  fi

  printf 'Could not read structured failures from xcresult; showing likely failure lines from xcodebuild log.\n' >&2
  grep -E "Test case '.*' failed|/[^:]+\.swift:[0-9]+: error:|XCTAssert|failed:" "$test_log" >&2 || true
}

remember_temp_file() {
  TEMP_FILES+=("$1")
}

remember_temp_path() {
  TEMP_PATHS+=("$1")
}

cleanup() {
  local path
  for path in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do
    [[ -n "$path" && -f "$path" ]] && rm -f "$path"
  done
  for path in "${TEMP_PATHS[@]+"${TEMP_PATHS[@]}"}"; do
    [[ -n "$path" && -e "$path" ]] && rm -rf "$path"
  done
}
trap cleanup EXIT

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing required file: $path"
}

require_executable() {
  local path="$1"
  [[ -x "$path" ]] || fail "required verifier is missing or not executable: $path"
}

require_fixed_string() {
  local path="$1"
  local pattern="$2"
  local message="$3"

  require_file "$path"
  if ! grep -Fq "$pattern" "$path"; then
    fail "$message ($path must contain: $pattern)"
  fi
}

require_extended_regex() {
  local path="$1"
  local pattern="$2"
  local message="$3"

  require_file "$path"
  if ! grep -Eq "$pattern" "$path"; then
    fail "$message ($path must match: $pattern)"
  fi
}

require_suite_declaration() {
  local path="$1"
  local suite_name="$2"

  require_extended_regex \
    "$path" \
    "^(final[[:space:]]+)?class[[:space:]]+${suite_name}[[:space:]]*:" \
    "missing expected XCTest suite declaration: $suite_name"
}

require_test_method() {
  local path="$1"
  local test_name="$2"
  local message="$3"

  require_extended_regex \
    "$path" \
    "^[[:space:]]*func[[:space:]]+${test_name}[[:space:]]*\\(" \
    "$message"
}

check_swift_file_size_limit() {
  log_section "Swift source-file size guard"

  local report
  report="$(mktemp -t quizice-s04-swift-loc.XXXXXX.log)"
  remember_temp_file "$report"

  # Bash 3.2 is still the system shell on GitHub's macOS runners. Feeding a
  # NUL-delimited file is more portable there than parsing a multiline process
  # substitution after the function has already been loaded.
  local swift_file_list
  swift_file_list="$(mktemp -t quizice-s04-swift-files.XXXXXX.list)"
  remember_temp_file "$swift_file_list"
  find Quizice \
    -type d -name DerivedData -prune -o \
    -type f -name '*.swift' -print0 > "$swift_file_list"

  local swift_file
  local line_count
  local allowed_line_count
  local legacy_entry
  local legacy_path
  local legacy_limit
  while IFS= read -r -d '' swift_file; do
    line_count="$(awk 'END { print NR }' "$swift_file")"
    allowed_line_count="$MAX_SWIFT_FILE_LINES"
    for legacy_entry in "${LEGACY_SWIFT_FILE_LINE_LIMITS[@]}"; do
      IFS='|' read -r legacy_path legacy_limit <<< "$legacy_entry"
      if [[ "$swift_file" == "$legacy_path" ]]; then
        allowed_line_count="$legacy_limit"
        break
      fi
    done
    if (( line_count > allowed_line_count )); then
      printf '%s\t%s\t(limit %s)\n' "$line_count" "$swift_file" "$allowed_line_count" >> "$report"
    fi
  done < "$swift_file_list"

  if [[ -s "$report" ]]; then
    printf 'Swift files exceeding %s lines:\n' "$MAX_SWIFT_FILE_LINES" >&2
    LC_ALL=C sort -k1,1nr -k2,2 "$report" >&2
    fail "Swift source files exceeded their ratcheted line limits"
  fi

  printf 'Production Swift files respect the %s-line limit and legacy ratchets: PASS\n' "$MAX_SWIFT_FILE_LINES"
  printf 'Swift files in QuiziceTests/ are exempt from the source-file size guard: PASS\n'
}

check_split_test_layout_and_markers() {
  log_section "Split XCTest layout and marker checks"

  local test_source
  for test_source in "${SPLIT_TEST_SOURCE_FILES[@]}"; do
    require_file "$test_source"
  done

  local removed_test_file
  for removed_test_file in "${REMOVED_TEST_FILES[@]}"; do
    if [[ -e "$removed_test_file" ]]; then
      fail "retired test file must remain removed: $removed_test_file"
    fi
  done

  local suite_entry
  local suite_file
  local suite_name
  for suite_entry in "${SPLIT_TEST_SUITE_LAYOUT[@]}"; do
    IFS='|' read -r suite_file suite_name <<< "$suite_entry"
    require_suite_declaration "$suite_file" "$suite_name"
  done

  require_extended_regex \
    "QuiziceTests/Support/UIView+TestDescendant.swift" \
    '^[[:space:]]*func[[:space:]]+descendant\(withAccessibilityIdentifier[[:space:]]+identifier:[[:space:]]+String\)' \
    'split cross-screen support must keep the accessibility descendant helper'

  require_test_method \
    "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizContractValidationTests.swift" \
    'testResponseMustContainTheRequestedQuestionCount' \
    'AI quiz contract tests must preserve requested-count validation'
  require_test_method \
    "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeErrorTests.swift" \
    'testURLCancellationIsPropagatedAsCancellationError' \
    'AI quiz error tests must preserve cancellation coverage'
  require_test_method \
    "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeRequestTests.swift" \
    'testRequestUsesResponsesAPIHeadersPromptAndJSONEncodedInput' \
    'AI quiz request tests must preserve the wire-request contract'
  require_test_method \
    "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeResponseTests.swift" \
    'testOutputTextFragmentsAreJoinedInWireOrder' \
    'AI quiz response tests must preserve ordered output-fragment coverage'
  require_test_method \
    "QuiziceTests/Features/AIQuiz/Unit/YandexAIQuizThemeTransportTests.swift" \
    'testMissingAPIKeyFailsBeforeStartingNetworkRequest' \
    'AI quiz transport tests must preserve missing-key coverage'

  require_test_method \
    "QuiziceTests/Features/AppFlow/Unit/QuizFlowCoordinatorLaunchTests.swift" \
    'testStartInstallsHomeControllerAsNavigationRoot' \
    'coordinator launch tests must preserve root installation coverage'
  require_test_method \
    "QuiziceTests/Features/AppFlow/Unit/QuizFlowCoordinatorNavigationTests.swift" \
    'testModalRoutesPresentQuestionResultAndSettings' \
    'coordinator navigation tests must preserve the active modal routes'
  require_test_method \
    "QuiziceTests/Features/AppFlow/Unit/QuizFlowCoordinatorAIThemeTests.swift" \
    'testInlineAIThemeSubmitIsSingleFlight' \
    'coordinator AI-theme tests must preserve single-flight coverage'
  require_test_method \
    "QuiziceTests/Features/AppFlow/Unit/QuizFlowCoordinatorAIThemeTests.swift" \
    'testInlineAIThemeSuccessUpdatesSessionAndRoutesToQuestionExactlyOnce' \
    'AI success tests must preserve the direct handoff from generation to Quiz Play'

  require_test_method \
    "QuiziceTests/Features/Home/Unit/HomeThemeCardReducerTests.swift" \
    'testFrontBackSelectionAndStartLifecycleLaunchesOnlyOnce' \
    'home theme-card reducer tests must preserve launch lifecycle coverage'
  require_test_method \
    "QuiziceTests/Features/Home/Unit/HomeAIThemeCardReducerTests.swift" \
    'testSubmissionIsSingleFlightAndDraftCannotMutateWhileRequestIsActive' \
    'home AI reducer tests must preserve single-flight state coverage'
  require_test_method \
    "QuiziceTests/Features/Home/Tests/HomeSettingsVisualStateTests.swift" \
    'testCleanSettingsSurfaceIsCircular' \
    'home settings tests must keep the Clean settings surface circular'
  require_test_method \
    "QuiziceTests/Features/Home/Tests/HomeCollectionServiceTests.swift" \
    'testCollectionServiceAppliesPolishedCardStylingWithoutChangingIdentifiers' \
    'home collection tests must preserve polished card styling coverage'
  require_test_method \
    "QuiziceTests/Features/Home/Tests/HomeCollectionServicePresentationTests.swift" \
    'testCompactStatisticsTitleShrinksAndLastItemOwnsBottomSpacing' \
    'home collection tests must preserve compact statistics spacing coverage'
  require_test_method \
    "QuiziceTests/Features/Home/Tests/HomeExpandedCardTransitionTests.swift" \
    'testStatisticsCardExpandsInlineTracksOnceAndRestoresTheGridWithoutQuizCancellation' \
    'inline statistics tests must preserve expansion, analytics, and grid restoration coverage'
  require_test_method \
    "QuiziceTests/Features/Home/Tests/HomeExpandedCardTransitionTests.swift" \
    'testExpandedStatisticsCardKeepsLargeHistoryValueVisibleAtNarrowWidths' \
    'inline statistics tests must keep large accumulated values visible on narrow phones'

  require_test_method \
    "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionTypographyContractTests.swift" \
    'testLongAnswersShrinkWithoutClippingAcrossSelectableStylesAndPhoneSizes' \
    'question typography tests must cover long-answer fitting across styles and phone sizes'
  require_test_method \
    "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionTypographyContractTests.swift" \
    'testInitialLongAnswersFitBeforeSelectionAndStayStableAfterFeedback' \
    'question typography tests must cover the initial frame before selection'
  require_test_method \
    "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionTypographyContractTests.swift" \
    'testLongAnswersPreserveAccessibilityFontsInScrollableContent' \
    'question typography tests must preserve Dynamic Type coverage'
  require_test_method \
    "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionTypographyContractTests.swift" \
    'testLongQuestionsFitAvailableCardHeightAcrossSelectableStylesAndPhoneSizes' \
    'question typography tests must bound long-question typography'
  require_test_method \
    "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionTypographyContractTests.swift" \
    'testExtremeQuestionRemainsReadableWithScrollableBody' \
    'question typography tests must fit extreme questions without scrolling'
  require_test_method \
    "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionTypographyContractTests.swift" \
    'testQuestionFontRestoresForShortQuestionAndRefitsAfterWidthChange' \
    'question typography tests must preserve refitting coverage'
  require_test_method \
    "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionStateContractTests.swift" \
    'testExtremeAnswerFitsWithoutGrowingCardOrMovingNextButton' \
    'question state tests must keep the card and next button fixed for long answers'
  require_test_method \
    "QuiziceTests/Features/QuizPlay/UIContracts/QuizQuestionStateContractTests.swift" \
    'testQuestionAdvanceKeepsCardFrameStableAfterLongAnswer' \
    'question state tests must keep the card frame stable when advancing'
  local split_test_count=0
  local source_test_count
  for test_source in "${SPLIT_TEST_SOURCE_FILES[@]}"; do
    source_test_count="$(grep -Ec '^[[:space:]]*func[[:space:]]+test' "$test_source" || true)"
    split_test_count=$((split_test_count + source_test_count))
  done
  if (( split_test_count < MIN_SPLIT_TEST_METHODS )); then
    fail "split feature/support test files expose only $split_test_count test methods; expected at least $MIN_SPLIT_TEST_METHODS"
  fi

  printf 'Split test files, suites, and at least %s preserved test methods: PASS\n' "$MIN_SPLIT_TEST_METHODS"
}

check_direct_ai_route_and_retired_description() {
  log_section "Direct AI route and retired Description contract"

  require_file "$AI_WORKFLOW"
  require_file "$QUIZ_FLOW_COORDINATOR"
  [[ ! -e "$RETIRED_DESCRIPTION_VIEW_CONTROLLER" ]] || \
    fail "standalone Description controller must remain removed: $RETIRED_DESCRIPTION_VIEW_CONTROLLER"
  if grep -Fq 'QuizDescriptionViewController.swift' "$PROJECT_FILE"; then
    fail "Xcode project still references the retired standalone Description controller"
  fi

  require_fixed_string "$AI_WORKFLOW" 'analytics.track(.themeSelected(theme: .ai, method: .ai))' 'AI success must retain typed theme-selection analytics'
  require_fixed_string 'Quizice/Features/QuizPlay/Presentation/QuizQuestionPresenter.swift' '.quizStarted(' 'Quiz Play must own quiz-start analytics'
  if grep -Fq '.quizStarted(' "$AI_WORKFLOW"; then
    fail 'AI generation must not duplicate the quiz-start event emitted by Quiz Play'
  fi
  require_fixed_string "$AI_WORKFLOW" 'quizTransitionSourceView = expandedAIThemeCardView' 'AI success must preserve the expanded card as the Question transition source'
  require_fixed_string "$AI_WORKFLOW" 'router.showQuestion()' 'AI success must route directly to Quiz Play'
  if grep -Fq 'router.showDescription()' "$AI_WORKFLOW"; then
    fail "AI success must not route through the retired Description screen"
  fi
  if grep -Eq 'func[[:space:]]+(showDescription|closeDescription)\(' "$QUIZ_FLOW_COORDINATOR"; then
    fail "coordinator must not expose retired Description routes"
  fi
  if grep -Fq 'QuizDescriptionRouting' "$QUIZ_FLOW_COORDINATOR"; then
    fail "coordinator must not retain the retired Description routing protocol"
  fi

  printf 'Direct AI-to-Question handoff and retired Description route: PASS\n'
}

file_sha256() {
  local path="$1"
  require_file "$path"
  shasum -a 256 "$path" | awk '{print $1}'
}

record_data_json_hash() {
  DATA_JSON_INITIAL_HASH="$(file_sha256 "$DATA_JSON")"
  printf 'Recorded %s SHA-256 before verifier workflow: %s\n' "$DATA_JSON" "$DATA_JSON_INITIAL_HASH"
}

assert_data_json_unchanged() {
  local current_hash
  current_hash="$(file_sha256 "$DATA_JSON")"
  if [[ "$current_hash" != "$DATA_JSON_INITIAL_HASH" ]]; then
    fail "$DATA_JSON was modified by the S04 verifier workflow (before: $DATA_JSON_INITIAL_HASH, after: $current_hash)"
  fi
  printf '%s preserved: PASS\n' "$DATA_JSON"
}

select_ios_simulator_udid() {
  if [[ -n "${QUIZICE_SIMULATOR_UDID:-}" ]]; then
    printf '%s\n' "$QUIZICE_SIMULATOR_UDID"
    return
  fi

  xcrun simctl list devices available -j | python3 -c '
import json
import sys

preferred_runtime = sys.argv[1]
preferred_device_type_suffix = sys.argv[2]
try:
    payload = json.load(sys.stdin)
except Exception as exc:
    raise SystemExit(f"could not parse simctl JSON: {exc}")

devices_by_runtime = payload.get("devices", {})
candidates = []
for runtime, devices in devices_by_runtime.items():
    if runtime != preferred_runtime:
        continue
    for device in devices:
        if not device.get("isAvailable", False):
            continue
        name = device.get("name", "")
        device_type = device.get("deviceTypeIdentifier", "")
        if not device_type.endswith(preferred_device_type_suffix):
            continue
        state = device.get("state", "")
        udid = device.get("udid", "")
        if udid:
            boot_rank = 0 if state == "Booted" else 1
            candidates.append((boot_rank, name, udid))

if not candidates:
    raise SystemExit(
        "snapshot host unavailable: create an iPhone 16e on iOS 26.2 "
        "or set QUIZICE_SIMULATOR_UDID to an explicitly compatible simulator"
    )

for _, _, udid in sorted(candidates):
    print(udid)
    break
' "$SNAPSHOT_RUNTIME_IDENTIFIER" "$SNAPSHOT_HOST_DEVICE_TYPE_SUFFIX"
}

assert_snapshot_recording_disabled() {
  local simulator_udid="$1"
  local key
  local value

  for key in QUIZICE_RECORD_SNAPSHOTS SNAPSHOT_TESTING_RECORD; do
    value="${!key:-}"
    [[ -z "$value" ]] || fail "$key must be unset while running the verifier"

    value="$(xcrun simctl spawn "$simulator_udid" launchctl getenv "$key" 2>/dev/null || true)"
    [[ -z "$value" ]] || fail "$key is set in the selected simulator; unset it before verification"
  done
}

check_project_and_test_wiring() {
  log_section "Project and XCTest target wiring checks"

  require_file "$PROJECT_FILE"
  require_file "$SMOKE_TESTS"
  require_file "$SUMMARY_TESTS"
  require_file "$STORE_TESTS"
  require_file "$PRESENTER_FAILURE_TESTS"
  require_file "$SNAPSHOT_SUPPORT_TESTS"
  require_file "$COMPONENT_SNAPSHOT_TESTS"
  require_file "$HOME_CARD_SNAPSHOT_TESTS"
  require_file "$SCREEN_SNAPSHOT_TESTS"
  require_file "$SWIFTUI_SNAPSHOT_TESTS"
  require_file "$APP_APPEARANCE_TESTS"
  require_file "$QUESTION_PRESENTER_TESTS"
  require_file "$QUIZ_FACTORY_TESTS"

  local test_source
  for test_source in "${SPLIT_TEST_SOURCE_FILES[@]}"; do
    require_file "$test_source"
  done

  local removed_test_file
  local removed_file_name
  for removed_test_file in "${REMOVED_TEST_FILES[@]}"; do
    [[ ! -e "$removed_test_file" ]] || fail "retired test file must remain removed: $removed_test_file"
    removed_file_name="$(basename "$removed_test_file")"
    if grep -Fq "$removed_file_name" "$PROJECT_FILE"; then
      fail "Xcode project still references retired test file: $removed_file_name"
    fi
  done

  if [[ "${QUIZICE_SKIP_XCODEBUILD:-0}" != "1" ]]; then
    local xcodebuild_list_log
    xcodebuild_list_log="$(mktemp -t quizice-s04-xcodebuild-list.XXXXXX.log)"
    remember_temp_file "$xcodebuild_list_log"
    xcodebuild \
      -skipPackagePluginValidation \
      -skipMacroValidation \
      -list \
      -project "$PROJECT" | tee "$xcodebuild_list_log"
    require_fixed_string "$xcodebuild_list_log" 'Quizice' 'Quizice scheme must be visible to xcodebuild'
  fi

  require_fixed_string "$PROJECT_FILE" 'QuiziceTests' 'QuiziceTests target must be present in the Xcode project'
  require_fixed_string "$PROJECT_FILE" 'productType = "com.apple.product-type.bundle.unit-test";' 'QuiziceTests must remain an XCTest unit-test bundle'
  require_fixed_string "$PROJECT_FILE" 'TestTargetID = 993C1BA82D8D5E8900AD9BE4;' 'QuiziceTests must remain app-hosted by the Quizice app target'
  require_fixed_string "$PROJECT_FILE" 'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Quizice.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Quizice";' 'QuiziceTests must keep a concrete app TEST_HOST'
  require_fixed_string "$PROJECT_FILE" 'BUNDLE_LOADER = "$(TEST_HOST)";' 'QuiziceTests must load through TEST_HOST'
  require_extended_regex "$PROJECT_FILE" 'QuiziceTests\.swift in Sources' 'QuiziceTests smoke test must remain in the test Sources build phase'
  require_extended_regex "$PROJECT_FILE" 'StatisticsSummaryTests\.swift in Sources' 'StatisticsSummaryTests must remain in the test Sources build phase'
  require_extended_regex "$PROJECT_FILE" 'StatisticsStoreTests\.swift in Sources' 'StatisticsStoreTests must remain in the test Sources build phase'
  require_extended_regex "$PROJECT_FILE" 'QuizQuestionPresenterFailureStateTests\.swift in Sources' 'QuizQuestionPresenterFailureStateTests must remain in the test Sources build phase'
  require_fixed_string "$PROJECT_FILE" 'https://github.com/pointfreeco/swift-snapshot-testing' 'Point-Free SnapshotTesting package must be referenced by the Xcode project'
  require_fixed_string "$PROJECT_FILE" 'SnapshotTesting in Frameworks' 'SnapshotTesting product must be linked into the test target'
  require_extended_regex "$PROJECT_FILE" 'SnapshotSupport\.swift in Sources' 'Snapshot support helpers must be in the test Sources build phase'
  require_extended_regex "$PROJECT_FILE" 'ComponentSnapshotTests\.swift in Sources' 'Component snapshot tests must be in the test Sources build phase'
  require_extended_regex "$PROJECT_FILE" 'HomeCardSnapshotTests\.swift in Sources' 'Home-card snapshot tests must be in the test Sources build phase'
  require_extended_regex "$PROJECT_FILE" 'ScreenSnapshotTests\.swift in Sources' 'Screen snapshot tests must be in the test Sources build phase'
  require_extended_regex "$PROJECT_FILE" 'SwiftUISnapshotTests\.swift in Sources' 'SwiftUI snapshot tests must be in the test Sources build phase'
  require_extended_regex "$PROJECT_FILE" 'AppAppearanceTests\.swift in Sources' 'App appearance tests must be in the test Sources build phase'
  require_extended_regex "$PROJECT_FILE" 'QuizQuestionPresenterTests\.swift in Sources' 'Expanded question presenter tests must be in the test Sources build phase'

  local test_file_name
  for test_source in "${SPLIT_TEST_SOURCE_FILES[@]}"; do
    test_file_name="$(basename "$test_source")"
    require_fixed_string \
      "$PROJECT_FILE" \
      "$test_file_name in Sources" \
      "$test_source must remain in the QuiziceTests Sources build phase"
  done

  require_fixed_string "$SMOKE_TESTS" '@testable import Quizice' 'Smoke tests must import the Quizice app module'

  printf 'Project contains the app-hosted QuiziceTests target and every split XCTest source: PASS\n'
}

check_statistics_coverage_markers() {
  log_section "R007 statistics coverage-marker checks"

  require_test_method "$SUMMARY_TESTS" 'testEmptySummaryHasZeroTotalsAndDisplayValues' 'Statistics tests must cover the empty summary baseline'
  require_test_method "$SUMMARY_TESTS" 'testSummaryAggregatesPlayedQuizzesCorrectAnswersAndTotalQuestions' 'Statistics tests must cover played quiz, correct-answer, and total-question aggregation'
  require_test_method "$SUMMARY_TESTS" 'testPercentageIsRoundedToNearestWholeNumber' 'Statistics tests must cover percentage rounding'
  require_test_method "$SUMMARY_TESTS" 'testBestResultDisplayUsesBestAttempt' 'Statistics tests must cover best-result display'
  require_test_method "$SUMMARY_TESTS" 'testBestResultSelectsMoreCorrectAnswersOverHigherPercentage' 'Statistics tests must cover server best-result precedence by correct-answer count'
  require_test_method "$SUMMARY_TESTS" 'testBestResultTieUsesMoreCorrectAnswers' 'Statistics tests must cover best-result tie handling'
  require_test_method "$SUMMARY_TESTS" 'testEqualCorrectAnswersKeepFirstAttempt' 'Statistics tests must keep the previous best result when correct-answer counts tie'
  require_test_method "$STORE_TESTS" 'testRecordAttemptPersistsValidAttempts' 'Statistics store tests must cover valid attempt persistence'

  printf 'R007 statistics marker checks: PASS\n'
}

check_failure_state_coverage_markers() {
  log_section "R008 local failure-state coverage-marker checks"

  require_test_method "$STORE_TESTS" 'testFirstRunLoadSummaryReturnsEmpty' 'Statistics store tests must cover first-run empty state'
  require_test_method "$STORE_TESTS" 'testLoadSummaryReturnsEmptyForCorruptPersistedBytesAndRemovesKey' 'Statistics store tests must cover corrupt persisted bytes'
  require_test_method "$STORE_TESTS" 'testLoadSummaryReturnsEmptyAndRemovesKeyForMalformedAttemptPayload' 'Statistics store tests must cover malformed persisted attempt payloads'
  require_test_method "$STORE_TESTS" 'testRecordAttemptIgnoresNonPositiveTotals' 'Statistics store tests must cover invalid non-positive totals'
  require_test_method "$STORE_TESTS" 'testRecordAttemptSanitizesCorrectAnswersOutsideValidRange' 'Statistics store tests must cover out-of-range correct-answer sanitization'

  require_test_method "$PRESENTER_FAILURE_TESTS" 'testNilChosenThemeShowsUnavailableQuestionState' 'Presenter failure-state tests must cover nil chosen theme'
  require_test_method "$PRESENTER_FAILURE_TESTS" 'testChosenThemeWithNoQuestionsShowsUnavailableQuestionState' 'Presenter failure-state tests must cover empty local question arrays'
  require_test_method "$PRESENTER_FAILURE_TESTS" 'testQuestionWithEmptyTextShowsUnavailableQuestionState' 'Presenter failure-state tests must cover malformed blank question text'
  require_test_method "$PRESENTER_FAILURE_TESTS" 'testQuestionWithFewerThanFourAnswersShowsUnavailableQuestionState' 'Presenter failure-state tests must cover malformed answer counts'
  require_test_method "$PRESENTER_FAILURE_TESTS" 'testQuestionWithEmptyCorrectAnswerShowsUnavailableQuestionState' 'Presenter failure-state tests must cover malformed blank correct answer'
  require_test_method "$PRESENTER_FAILURE_TESTS" 'testQuestionWithDuplicatedCorrectAnswerShowsUnavailableQuestionState' 'Presenter failure-state tests must cover ambiguous duplicate correct-answer titles'
  require_test_method "$PRESENTER_FAILURE_TESTS" 'testAnswerSelectionUsesOptionID' 'Presenter tests must cover answer selection by option id'

  if grep -Fq "$DATA_JSON" "$SUMMARY_TESTS" "$STORE_TESTS" "$PRESENTER_FAILURE_TESTS"; then
    fail "S04 tests must use synthetic fixtures and isolated UserDefaults, not mutable $DATA_JSON"
  fi

  printf 'R008 failure-state marker checks: PASS\n'
}

check_snapshot_coverage_markers() {
  log_section "Snapshot and expanded unit coverage-marker checks"

  require_fixed_string "$SNAPSHOT_SUPPORT_TESTS" 'import SnapshotTesting' 'Snapshot support must import Point-Free SnapshotTesting'
  require_test_method "$COMPONENT_SNAPSHOT_TESTS" 'testPrimaryButtonsAcrossDesignStyles' 'Component snapshots must cover primary buttons across styles'
  require_test_method "$COMPONENT_SNAPSHOT_TESTS" 'testSecondaryButtonsAcrossDesignStyles' 'Component snapshots must cover secondary buttons across styles'
  require_test_method "$HOME_CARD_SNAPSHOT_TESTS" 'testThemeCardSnapshot' 'Home card snapshots must cover theme cards'
  require_test_method "$HOME_CARD_SNAPSHOT_TESTS" 'testRadarLongThemeCompactCardSnapshot' 'Home card snapshots must cover long Radar titles on compact phones'
  require_fixed_string "$HOME_CARD_SNAPSHOT_TESTS" 'let requiredTitleHeight = title.sizeThatFits(' 'Long Radar title regression must measure UIKit word wrapping before accepting a snapshot'
  require_fixed_string "$HOME_CARD_SNAPSHOT_TESTS" 'assertTitleFits(stage: "before snapshot hosting")' 'Long Radar title regression must verify the collection cell layout before snapshot hosting'
  require_fixed_string "$HOME_CARD_SNAPSHOT_TESTS" 'assertTitleFits(stage: "after snapshot hosting")' 'Long Radar title regression must preserve full title layout during snapshot hosting'
  require_test_method "$HOME_COLLECTION_TESTS" 'testClassicThemeCardsFitFullTitlesAcrossDynamicTypeAndCatalogWidths' 'Classic theme cards must have full-title layout coverage across Dynamic Type sizes and catalog widths'
  require_test_method "$HOME_COLLECTION_TESTS" 'testCleanThemeCardsFitFullTitlesAcrossDynamicTypeAndCatalogWidths' 'Clean theme cards must have full-title layout coverage across Dynamic Type sizes and catalog widths'
  require_test_method "$HOME_COLLECTION_TESTS" 'testRadarThemeCardsFitFullTitlesAcrossDynamicTypeAndCatalogWidths' 'Radar theme cards must have full-title layout coverage across Dynamic Type sizes and catalog widths'
  require_extended_regex "$HOME_COLLECTION_TESTS" 'XCTAssertLessThanOrEqual\(ceil\(requiredTitleHeight\), title\.bounds\.height' 'Adaptive theme tests must verify the complete measured title fits vertically'
  require_extended_regex "$HOME_COLLECTION_TESTS" 'XCTAssertLessThanOrEqual\(widestWord, title\.bounds\.width' 'Adaptive theme tests must verify whole title words fit horizontally'
  local coordinate
  for coordinate in minX minY width height; do
    require_fixed_string "$HOME_COLLECTION_TESTS" "XCTAssertEqual(transitionTitle.frame.$coordinate, titleFrame.$coordinate," 'Adaptive theme tests must preserve source title geometry in transition snapshots'
  done
  require_test_method "$HOME_CARD_SNAPSHOT_TESTS" 'testCompactStatisticsCardSnapshot' 'Home card snapshots must cover compact statistics layout'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testHomeScreenSnapshot' 'Screen snapshots must cover home'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testHomeCompactPortraitSnapshot' 'Screen snapshots must cover the home screen on iPhone SE geometry'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testHomeCompactPortraitBottomSnapshot' 'Screen snapshots must cover the final home item and its internal bottom spacing'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testRadarExpandedStatisticsLargeHistorySnapshot' 'Screen snapshots must cover inline Radar statistics with a large history'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testClassicLongAnswerModernPortraitSnapshot' 'Screen snapshots must reproduce long answers on iPhone 17 Pro Classic layout'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testClassicLongAnswerCompactPortraitSnapshot' 'Screen snapshots must reproduce long answers on compact Classic layout'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testRadarLongAnswerModernPortraitSnapshot' 'Screen snapshots must cover long answers on iPhone 17 Pro Radar layout'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testRadarLongAnswerCompactPortraitSnapshot' 'Screen snapshots must cover long answers on compact Radar layout'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testRadarJapanQuestionInitialModernPortraitSnapshot' 'Screen snapshots must cover the reported initial Radar layout on iPhone 17 Pro'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testRadarJapanQuestionInitialCompactPortraitSnapshot' 'Screen snapshots must cover the reported long question on compact Radar layout'
  require_test_method "$SCREEN_SNAPSHOT_TESTS" 'testCleanLongAnswerCompactPortraitSnapshot' 'Screen snapshots must cover long answers on compact Clean layout'
  require_fixed_string "$SCREEN_SNAPSHOT_TESTS" '«Поступай так, чтобы максима твоей воли могла бы быть всеобщим законом»' 'Screen snapshots must reproduce the reported long-answer fixture'
  require_fixed_string "$SCREEN_SNAPSHOT_TESTS" 'Какое событие положило конец периоду феодальной раздробленности' 'Screen snapshots must reproduce the reported long-question fixture'
  require_test_method "$SWIFTUI_SNAPSHOT_TESTS" 'testSettingsViewSnapshot' 'SwiftUI snapshots must cover settings'
  require_test_method "$SWIFTUI_SNAPSHOT_TESTS" 'testClassicSettingsCompactPortraitSnapshot' 'SwiftUI snapshots must cover Classic settings on iPhone SE geometry'
  require_fixed_string \
    "QuiziceTests/Features/Home/Tests/HomeCollectionServiceTests.swift" \
    'XCTAssertEqual(themeCell.layer.shadowOpacity, 0)' \
    'Home collection tests must keep Clean light theme cards shadowless'
  require_fixed_string "$APP_APPEARANCE_TESTS" 'testAllDesignStylesResolveExpectedSurfaceFamilies' 'Appearance tests must cover all design styles'
  require_fixed_string "$QUESTION_PRESENTER_TESTS" 'testCorrectAnswerRecordsSingleCompletedAttemptAndEmitsResult' 'Question presenter tests must cover result emission and statistics recording'
  require_fixed_string "$QUIZ_FACTORY_TESTS" 'testSwiftDataThemeStoreReplacesFetchesAndClearsThemes' 'Factory tests must cover in-memory SwiftData theme store behavior'

  printf 'Snapshot and expanded unit coverage-marker checks: PASS\n'
}

run_app_build() {
  log_section "App build"
  xcodebuild \
    -quiet \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphonesimulator \
    CODE_SIGNING_ALLOWED=NO \
    build
  printf 'App build: PASS\n'
}

check_coverage() {
  local result_bundle="$1"
  local coverage_json
  coverage_json="$(mktemp -t quizice-s04-xccov.XXXXXX.json)"
  remember_temp_file "$coverage_json"

  xcrun xccov view --report --json "$result_bundle" > "$coverage_json"
  python3 - "$coverage_json" "$MIN_LINE_COVERAGE_PERCENT" <<'PY'
import json
import sys

path = sys.argv[1]
minimum = float(sys.argv[2])
with open(path, "r", encoding="utf-8") as handle:
    report = json.load(handle)

targets = report.get("targets", [])
app_targets = [
    target for target in targets
    if target.get("name") in {"Quizice.app", "Quizice"}
    or (target.get("name", "").startswith("Quizice") and "Tests" not in target.get("name", ""))
]

if not app_targets:
    raise SystemExit("could not find Quizice app target in xccov report")

target = sorted(app_targets, key=lambda item: item.get("executableLines", 0), reverse=True)[0]
line_coverage = target.get("lineCoverage")
if line_coverage is None:
    raise SystemExit("Quizice app target did not include lineCoverage")

percent = line_coverage * 100
print(f"Quizice app line coverage: {percent:.2f}%")
if percent + 1e-9 < minimum:
    raise SystemExit(f"line coverage {percent:.2f}% is below required {minimum:.0f}%")
PY
  printf 'Coverage threshold (%s%%): PASS\n' "$MIN_LINE_COVERAGE_PERCENT"
}

run_unit_tests() {
  log_section "Simulator selection"
  local simulator_udid
  simulator_udid="$(select_ios_simulator_udid)"
  [[ -n "$simulator_udid" ]] || fail "simulator selection returned an empty UDID"
  printf 'Selected iOS Simulator: %s\n' "$simulator_udid"
  assert_snapshot_recording_disabled "$simulator_udid"

  log_section "XCTest suite"
  local test_log
  test_log="$(mktemp -t quizice-s04-xctest.XXXXXX.log)"
  remember_temp_file "$test_log"
  local result_directory
  result_directory="$(mktemp -d "${TMPDIR:-/tmp}/quizice-s04-result.XXXXXX")"
  remember_temp_path "$result_directory"
  local result_bundle="$result_directory/QuiziceTests.xcresult"

  if ! xcodebuild \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=iOS Simulator,id=$simulator_udid" \
    CODE_SIGNING_ALLOWED=NO \
    -parallel-testing-enabled NO \
    -enableCodeCoverage YES \
    -resultBundlePath "$result_bundle" \
    test | tee "$test_log" >/dev/null; then
    print_xctest_failure_summary "$result_bundle" "$test_log"
    printf 'XCTest log retained at: %s\n' "$test_log" >&2
    fail "xcodebuild test failed"
  fi

  require_extended_regex "$test_log" "Test Case '-\\[QuiziceTests\\.QuiziceTests testQuiziceModuleLoads\\]' passed|Test Suite 'QuiziceTests' passed|Test case 'QuiziceTests\\.testQuiziceModuleLoads\\(\\)' passed" \
    'QuiziceTests smoke XCTest did not appear to execute'
  require_extended_regex "$test_log" "Test Suite 'StatisticsSummaryTests' passed|Test case 'StatisticsSummaryTests\\." \
    'StatisticsSummaryTests did not appear to execute'
  require_extended_regex "$test_log" "Test Suite 'StatisticsStoreTests' passed|Test case 'StatisticsStoreTests\\." \
    'StatisticsStoreTests did not appear to execute'
  require_extended_regex "$test_log" "Test Suite 'QuizQuestionPresenterFailureStateTests' passed|Test case 'QuizQuestionPresenterFailureStateTests\\." \
    'QuizQuestionPresenterFailureStateTests did not appear to execute'
  require_extended_regex "$test_log" "Test Suite 'ComponentSnapshotTests' passed|Test case 'ComponentSnapshotTests\\." \
    'ComponentSnapshotTests did not appear to execute'
  require_extended_regex "$test_log" "Test Suite 'ScreenSnapshotTests' passed|Test case 'ScreenSnapshotTests\\." \
    'ScreenSnapshotTests did not appear to execute'
  require_extended_regex "$test_log" "Test Suite 'HomeCardSnapshotTests' passed|Test case 'HomeCardSnapshotTests\\." \
    'HomeCardSnapshotTests did not appear to execute'
  require_extended_regex "$test_log" "Test Suite 'SwiftUISnapshotTests' passed|Test case 'SwiftUISnapshotTests\\." \
    'SwiftUISnapshotTests did not appear to execute'
  require_extended_regex "$test_log" "Test Suite 'HomeCollectionServiceTests' passed|Test case 'HomeCollectionServiceTests\\." \
    'HomeCollectionServiceTests did not appear to execute'
  require_extended_regex "$test_log" "Test Suite 'QuizQuestionTypographyContractTests' passed|Test case 'QuizQuestionTypographyContractTests\\." \
    'QuizQuestionTypographyContractTests did not appear to execute'
  require_extended_regex "$test_log" "Test Suite 'AppAppearanceTests' passed|Test case 'AppAppearanceTests\\." \
    'AppAppearanceTests did not appear to execute'

  printf 'XCTest suite: PASS\n'
  check_coverage "$result_bundle"
}

log_section "Required files and data preservation baseline"
require_executable "$S03_VERIFIER"
require_file "$PROJECT_FILE"
require_file "$DATA_JSON"
record_data_json_hash

log_section "S03 delegated verifier"
"$S03_VERIFIER"
printf 'S03 delegated verifier: PASS\n'
assert_data_json_unchanged

check_project_and_test_wiring
check_swift_file_size_limit
check_split_test_layout_and_markers
check_direct_ai_route_and_retired_description
check_statistics_coverage_markers
check_failure_state_coverage_markers
check_snapshot_coverage_markers
assert_data_json_unchanged

if [[ "$VERIFIER_MODE" == "--checks-only" ]]; then
  log_section "S04 static verifier result"
  printf 'S01-S04 contracts, test wiring, coverage markers, and %s preservation: PASS\n' "$DATA_JSON"
  printf '✅ S04 static test infrastructure verification passed.\n'
  exit 0
fi

run_app_build
assert_data_json_unchanged
run_unit_tests
assert_data_json_unchanged

log_section "S04 verifier result"
printf 'S03 delegation, app build, unit tests, coverage-marker checks, and %s preservation: PASS\n' "$DATA_JSON"
printf '✅ S04 tests and failure states verifier: PASS\n'
