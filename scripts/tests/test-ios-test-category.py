#!/usr/bin/env python3
"""Exercise simulator cleanup without starting Xcode or a real simulator."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "run-ios-test-category.sh"
EXISTING_UDID = "11111111-1111-1111-1111-111111111111"
CREATED_UDID = "22222222-2222-2222-2222-222222222222"

TOOL_STUB = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

tool = Path(sys.argv[0]).name
arguments = sys.argv[1:]
with open(os.environ["STUB_EVENTS"], "a", encoding="utf-8") as handle:
    handle.write(json.dumps([tool, *arguments]) + "\n")

failure = os.environ["STUB_XCODEBUILD_FAILURE"] == "1"
if tool == "xcodebuild":
    result = arguments[arguments.index("-resultBundlePath") + 1]
    Path(result).mkdir(parents=True)
    raise SystemExit(65 if failure else 0)

if arguments == ["simctl", "list", "-j"]:
    runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
    device_type = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
    state = os.environ["STUB_INITIAL_STATE"]
    devices = [] if state == "Missing" else [{
        "name": "iPhone 17", "udid": os.environ["STUB_EXISTING_UDID"],
        "deviceTypeIdentifier": device_type, "state": state,
        "isAvailable": True,
    }]
    print(json.dumps({
        "runtimes": [{"identifier": runtime, "version": "26.2", "isAvailable": True}],
        "devicetypes": [{"name": "iPhone 17", "identifier": device_type}],
        "devices": {runtime: devices},
    }))
elif arguments[:2] == ["simctl", "create"]:
    print(os.environ["STUB_CREATED_UDID"])
elif arguments[:2] == ["simctl", "boot"]:
    if os.environ["STUB_INITIAL_STATE"] in {"Booted", "Booting"}:
        raise SystemExit(149)
elif arguments[:2] in (["simctl", "bootstatus"], ["simctl", "shutdown"], ["simctl", "delete"]):
    pass
elif arguments[:4] == ["xcresulttool", "get", "test-results", "summary"]:
    print(json.dumps({
        "totalTestCount": 1, "passedTests": 0 if failure else 1,
        "failedTests": 1 if failure else 0, "skippedTests": 0,
    }))
elif arguments[:3] == ["xccov", "view", "--report"]:
    print(json.dumps({"targets": [{
        "name": "Quizice.app", "executableLines": 10, "lineCoverage": 1.0,
    }]}))
else:
    raise SystemExit(f"Unexpected stub invocation: {tool} {arguments!r}")
'''


class SimulatorCleanupTests(unittest.TestCase):
    def run_category(self, initial_state, *, failure=False):
        with tempfile.TemporaryDirectory(prefix="quizice-category-tests-") as directory:
            root = Path(directory)
            runner = root / "scripts" / SCRIPT.name
            runner.parent.mkdir()
            shutil.copyfile(SCRIPT, runner)

            sources = {
                "QuiziceTests/Unit/FixtureTests.swift": "FixtureTests",
                "QuiziceTests/Features/Home/Tests/HomeFixtureTests.swift": "HomeFixtureTests",
                "QuiziceTests/Snapshots/SnapshotFixtureTests.swift": "SnapshotFixtureTests",
            }
            for relative_path, suite in sources.items():
                source = root / relative_path
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text(
                    f"final class {suite}: XCTestCase {{\n"
                    "    func testFixture() {}\n}\n", encoding="utf-8",
                )

            binaries = root / "bin"
            binaries.mkdir()
            # Keep every Python process and Apple tool on this isolated PATH.
            (binaries / "python3").symlink_to(sys.executable)
            for tool in ("xcrun", "xcodebuild"):
                stub = binaries / tool
                stub.write_text(TOOL_STUB, encoding="utf-8")
                stub.chmod(0o755)

            events_path = root / "events.jsonl"
            environment = {
                key: value for key, value in os.environ.items()
                if not key.startswith("QUIZICE_") and key != "GITHUB_STEP_SUMMARY"
            }
            environment.update({
                "PATH": f"{binaries}:/usr/bin:/bin:/usr/sbin:/sbin",
                "TMPDIR": str(root) + "/",
                "QUIZICE_TEST_ACTION": "test-without-building",
                "STUB_EVENTS": str(events_path),
                "STUB_INITIAL_STATE": initial_state,
                "STUB_XCODEBUILD_FAILURE": "1" if failure else "0",
                "STUB_EXISTING_UDID": EXISTING_UDID,
                "STUB_CREATED_UDID": CREATED_UDID,
            })
            result = subprocess.run(
                ["/bin/bash", str(runner), "unit", "iPhone 17", "26.2"],
                cwd=root, env=environment, capture_output=True, text=True,
                timeout=20, check=False,
            )
            events = [json.loads(line) for line in events_path.read_text().splitlines()]
            diagnostic = result.stdout + result.stderr
            self.assertEqual(sum(event[0] == "xcodebuild" for event in events), 1, diagnostic)
            if failure:
                self.assertNotEqual(result.returncode, 0, diagnostic)
                self.assertIn("xcodebuild unit tests failed", diagnostic)
            else:
                self.assertEqual(result.returncode, 0, diagnostic)
                self.assertIn("unit tests passed", diagnostic)
            return events

    def assert_cleanup(self, events, *, shutdown=(), delete=()):
        for command, expected in (("shutdown", shutdown), ("delete", delete)):
            actual = [
                event[3:] for event in events
                if event[:3] == ["xcrun", "simctl", command]
            ]
            self.assertEqual(actual, [[udid] for udid in expected], events)

    def test_reused_shutdown_simulator_is_stopped_after_success(self):
        events = self.run_category("Shutdown")
        self.assert_cleanup(events, shutdown=(EXISTING_UDID,))

    def test_reused_shutdown_simulator_is_stopped_after_failure(self):
        events = self.run_category("Shutdown", failure=True)
        self.assert_cleanup(events, shutdown=(EXISTING_UDID,))

    def test_existing_active_simulators_are_preserved(self):
        for state in ("Booted", "Booting"):
            for failure in (False, True):
                with self.subTest(state=state, failure=failure):
                    self.assert_cleanup(self.run_category(state, failure=failure))

    def test_created_simulator_is_stopped_and_deleted_after_success(self):
        events = self.run_category("Missing")
        self.assert_cleanup(events, shutdown=(CREATED_UDID,), delete=(CREATED_UDID,))

    def test_created_simulator_is_stopped_and_deleted_after_failure(self):
        events = self.run_category("Missing", failure=True)
        self.assert_cleanup(events, shutdown=(CREATED_UDID,), delete=(CREATED_UDID,))


if __name__ == "__main__":
    unittest.main()
