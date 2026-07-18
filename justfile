# Big Immich developer tasks. Run `just` to see everything.

project := "app/BigImmich.xcodeproj"
scheme := "Big Immich"
destination := "platform=tvOS Simulator,name=Apple TV"

# Point at real Xcode without needing `sudo xcode-select`. Override by exporting
# DEVELOPER_DIR yourself (CI sets it to the runner's Xcode).
export DEVELOPER_DIR := env_var_or_default("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")

_default:
    @just --list

# Compile the app and all targets for the tvOS simulator.
build:
    xcodebuild build -project "{{project}}" -scheme "{{scheme}}" \
        -destination "{{destination}}" CODE_SIGNING_ALLOWED=NO

# Compile in Release (-O, whole-module) for a device, mirroring the archive build.
# The Debug build and the tests run unoptimized, so they miss optimizer-only
# failures (e.g. a SIL inliner crash on a generic class's deinit). This catches them.
build-release:
    xcodebuild build -project "{{project}}" -scheme "{{scheme}}" \
        -configuration Release -destination "generic/platform=tvOS" \
        CODE_SIGNING_ALLOWED=NO

# Run the standard test suite (unit + launch UI test) on the tvOS simulator.
# The end-to-end slideshow journey is excluded; it needs the mock server
# (see `just e2e-snapshots`).
test:
    xcodebuild test -project "{{project}}" -scheme "{{scheme}}" \
        -skip-testing:BigImmichUITests/SlideshowJourneyUITests \
        -destination "{{destination}}" CODE_SIGNING_ALLOWED=NO

# Run only the fast logic unit tests.
test-unit:
    xcodebuild test -project "{{project}}" -scheme "{{scheme}}" \
        -only-testing:BigImmichTests \
        -destination "{{destination}}" CODE_SIGNING_ALLOWED=NO

# Run the unit tests with code coverage and print a per-file report. Informational
# only — not a CI gate and nothing fails on a low number.
coverage:
    #!/usr/bin/env bash
    set -euo pipefail
    out="$(mktemp -d)/coverage.xcresult"
    xcodebuild test -project "{{project}}" -scheme "{{scheme}}" \
        -only-testing:BigImmichTests \
        -destination "{{destination}}" -enableCodeCoverage YES \
        -resultBundlePath "$out" CODE_SIGNING_ALLOWED=NO
    xcrun xccov view --report "$out"

# Apply lint autocorrect then formatting (SwiftFormat has the final say on layout).
format:
    swiftlint --fix --quiet
    swiftformat app

# Verify formatting without editing files (CI gate).
format-check:
    swiftformat app --lint

# Lint. Advisory: fails only on error-severity rules, not warnings.
lint:
    swiftlint lint --quiet

# Scan the working tree and history for committed secrets.
security:
    gitleaks detect --config .gitleaks.toml --no-banner --redact

# Everything the fast CI runs, in order. Run this before pushing.
ci: format-check lint security build build-release test

# Report whether the vendored Immich OpenAPI spec drifted from the latest
# upstream spec (fast, no simulator or mock server needed).
openapi-drift:
    cd test && uv sync --quiet && uv run python openapi/check.py --drift-only

# Validate the mock server against the vendored spec and report drift.
openapi-check:
    #!/usr/bin/env bash
    set -euo pipefail
    cd test && uv sync --quiet
    uv run python mock-immich/server.py --port 8123 &
    trap 'kill %1 2>/dev/null || true' EXIT
    sleep 3
    uv run python openapi/check.py --mock-url http://127.0.0.1:8123

# End-to-end: start the mock Immich server, run the slideshow journey against
# it and export a screenshot of each screen into test/snapshots/.
e2e-snapshots:
    #!/usr/bin/env bash
    set -euo pipefail
    cd test && uv sync --quiet
    uv run python mock-immich/server.py --port 8123 &
    trap 'kill %1 2>/dev/null || true' EXIT
    sleep 3
    uv run python openapi/check.py --mock-url http://127.0.0.1:8123
    cd ..
    rm -rf test/snapshots && mkdir -p test/snapshots
    result="test/snapshots/result.xcresult"
    # Capture screenshots even when an assertion fails (the test keeps going
    # via continueAfterFailure), then surface the test's status.
    set +e
    xcodebuild test -project "{{project}}" -scheme "{{scheme}}" \
        -only-testing:BigImmichUITests/SlideshowJourneyUITests \
        -destination "{{destination}}" \
        -resultBundlePath "$result" \
        CODE_SIGNING_ALLOWED=NO
    status=$?
    set -e
    xcrun xcresulttool export attachments --path "$result" --output-path test/snapshots || true
    python3 test/rename_snapshots.py test/snapshots
    echo "Screenshots exported to test/snapshots/ (test status: $status)"
    exit $status
