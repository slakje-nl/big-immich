"""Two safety nets for the mock Immich server:

1. Conformance: validate the running mock's responses against the vendored
   Immich OpenAPI spec, for every endpoint the app relies on. Fails (exit 1)
   if the mock diverges from the spec.
2. Drift: compare the vendored spec against the latest Immich spec for the
   endpoints/schemas the app uses, and report differences. Warns by default;
   fails only with --strict-drift.

Usage:
  uv run python openapi/check.py --mock-url http://127.0.0.1:8123
"""

import argparse
import json
import sys
import warnings
from pathlib import Path

import requests
from jsonschema import RefResolver
from openapi_schema_validator import OAS30Validator

warnings.filterwarnings("ignore")

SPEC_PATH = Path(__file__).parent / "immich-openapi-specs.json"
LATEST_SPEC_URL = (
    "https://raw.githubusercontent.com/immich-app/immich/main/"
    "open-api/immich-openapi-specs.json"
)

USED_PATHS = [
    ("get", "/server/version"),
    ("get", "/albums"),
    ("get", "/albums/{id}"),
    ("post", "/search/metadata"),
    ("get", "/assets/{id}"),
    ("post", "/auth/login"),
]

USED_SCHEMAS = [
    "AlbumResponseDto",
    "AssetResponseDto",
    "ExifResponseDto",
    "SearchResponseDto",
    "SearchAssetResponseDto",
    "ServerVersionResponseDto",
]


def response_schema(spec, path, method):
    op = spec.get("paths", {}).get(path, {}).get(method, {})
    responses = op.get("responses", {})
    for status in sorted(responses):
        if status.startswith("2"):
            content = responses[status].get("content", {})
            schema = content.get("application/json", {}).get("schema")
            if schema is not None:
                return schema
    return None


def validate_mock(spec, mock_url) -> int:
    resolver = RefResolver.from_schema(spec)
    albums = requests.get(f"{mock_url}/api/albums").json()
    album_id = albums[0]["id"]
    asset_id = albums[0]["albumThumbnailAssetId"]

    responses = {
        ("get", "/server/version"): requests.get(f"{mock_url}/api/server/version").json(),
        ("get", "/albums"): albums,
        ("get", "/albums/{id}"): requests.get(f"{mock_url}/api/albums/{album_id}").json(),
        ("post", "/search/metadata"): requests.post(
            f"{mock_url}/api/search/metadata", json={"albumIds": [album_id]}
        ).json(),
        ("get", "/assets/{id}"): requests.get(f"{mock_url}/api/assets/{asset_id}").json(),
        ("post", "/auth/login"): requests.post(
            f"{mock_url}/api/auth/login", json={"email": "x", "password": "y"}
        ).json(),
    }

    failures = 0
    for method, path in USED_PATHS:
        schema = response_schema(spec, path, method)
        validator = OAS30Validator(schema, resolver=resolver)
        errors = sorted(validator.iter_errors(responses[(method, path)]), key=lambda e: list(e.path))
        if errors:
            failures += 1
            print(f"✗ {method.upper()} {path}: {len(errors)} conformance error(s)")
            for error in errors[:8]:
                print(f"    {list(error.path)}: {error.message[:110]}")
        else:
            print(f"✓ {method.upper()} {path} conforms to the spec")
    return failures


def check_drift(spec) -> int:
    try:
        latest = requests.get(LATEST_SPEC_URL, timeout=30).json()
    except requests.RequestException as error:
        print(f"! could not fetch the latest spec ({error}); skipping drift check")
        return 0

    vendored_version = spec["info"]["version"]
    latest_version = latest["info"]["version"]
    print(f"\nvendored Immich spec: {vendored_version}; latest: {latest_version}")

    diffs = 0
    for method, path in USED_PATHS:
        if response_schema(spec, path, method) != response_schema(latest, path, method):
            diffs += 1
            print(f"  ~ {method.upper()} {path} response schema changed upstream")

    for name in USED_SCHEMAS:
        vendored = spec.get("components", {}).get("schemas", {}).get(name)
        upstream = latest.get("components", {}).get("schemas", {}).get(name)
        if json.dumps(vendored, sort_keys=True) != json.dumps(upstream, sort_keys=True):
            diffs += 1
            print(f"  ~ schema {name} changed upstream")

    if diffs == 0 and vendored_version == latest_version:
        print("  no drift in the endpoints/schemas the app uses")
    elif diffs:
        print(
            f"  {diffs} difference(s): re-vendor the spec and review the models/mock "
            "if the app depends on the changed parts"
        )
    return diffs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mock-url", default="http://127.0.0.1:8123")
    parser.add_argument("--skip-drift", action="store_true")
    parser.add_argument("--strict-drift", action="store_true")
    parser.add_argument(
        "--drift-only",
        action="store_true",
        help="only check spec drift; no running mock server required",
    )
    args = parser.parse_args()

    spec = json.loads(SPEC_PATH.read_text())

    failures = 0
    if not args.drift_only:
        print("== mock conformance ==")
        failures = validate_mock(spec, args.mock_url)

    drift = 0
    if not args.skip_drift:
        print("\n== spec drift ==")
        drift = check_drift(spec)

    if failures:
        print(f"\nFAILED: mock diverges from the spec ({failures} endpoint(s))")
        return 1
    if args.strict_drift and drift:
        print(f"\nFAILED: spec drift detected ({drift} difference(s))")
        return 1
    print("\nOK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
