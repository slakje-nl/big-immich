# End-to-end test tooling

An offline slideshow journey: a mock Immich server the app talks to over real
HTTP, plus checks that keep the mock honest against the Immich API.

## Layout

- `mock-immich/server.py` — FastAPI mock of the endpoints the app uses
  (`/server/version`, `/albums`, `/albums/{id}`, `/search/metadata`,
  `/assets/{id}`, `/assets/{id}/thumbnail`, `/auth/login`). Serves real
  PIL-generated JPEGs so a slideshow actually renders.
- `openapi/immich-openapi-specs.json` — vendored Immich OpenAPI spec.
- `openapi/check.py` — validates the mock's responses against the vendored
  spec (fails on divergence) and reports drift vs the latest upstream spec.
- `pyproject.toml` / `uv.lock` — Python deps, pinned with [uv](https://docs.astral.sh/uv/).

## Running it

From the repo root:

```sh
just e2e-snapshots   # start mock -> run the journey -> export screenshots
just openapi-check   # validate the mock against the spec + report drift
just openapi-drift   # drift only (fast, no server)
```

Screenshots land in `test/snapshots/` (gitignored): first boot, settings
before/after configuring, albums, album details, album assets, slideshow and
paused slideshow.

The app is pointed at the mock via launch arguments the UI test passes
(`-uiTestImmichURL`, `-uiTestImmichAPIKey`, `-uiTestReset`); these only take
effect when set, so normal launches are unaffected.

## When the spec drifts

If `openapi-drift` reports differences, Immich changed the API. Re-vendor the
spec (download `open-api/immich-openapi-specs.json` from the Immich repo into
`openapi/`), then review the models in `app/ImmichAPI` and the mock for any
part the app depends on.

## CI

All the Immich checks live in a **separate** workflow, `e2e.yml`, which runs
on pushes to `main` and on manual dispatch: it runs the OpenAPI conformance +
drift check and the slideshow journey, uploading the screenshots as an
artifact. The fast `ci.yml` (every push/PR) does not touch Immich.
