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

# Run the full test suite (unit + UI) on the tvOS simulator.
test:
    xcodebuild test -project "{{project}}" -scheme "{{scheme}}" \
        -destination "{{destination}}" CODE_SIGNING_ALLOWED=NO

# Run only the fast logic unit tests.
test-unit:
    xcodebuild test -project "{{project}}" -scheme "{{scheme}}" \
        -only-testing:BigImmichTests \
        -destination "{{destination}}" CODE_SIGNING_ALLOWED=NO

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

# Everything CI runs, in order. Run this before pushing.
ci: format-check lint security build test
