"""A minimal mock of the Immich v3 API, just enough for the Big Immich
end-to-end snapshot test to browse albums and run a slideshow offline.

Only the endpoints the app calls are implemented, and their responses are
kept conformant with the vendored Immich OpenAPI spec (validated by
test/openapi/check.py). Any x-api-key is accepted.

Run: uv run python mock-immich/server.py --port 8123
"""

import argparse
import hashlib
import io

import uvicorn
from fastapi import FastAPI, Request, Response
from PIL import Image, ImageDraw

app = FastAPI()

OWNER_ID = "00000000-0000-4000-8000-000000000000"

ALBUMS = [
    {
        "id": "10000000-0000-4000-8000-000000000001",
        "albumName": "Vacation",
        "thumbnail": "20000000-0000-4000-8000-000000000001",
        "startDate": "2025-06-01T00:00:00.000Z",
        "assets": [
            "20000000-0000-4000-8000-000000000001",
            "20000000-0000-4000-8000-000000000002",
            "20000000-0000-4000-8000-000000000003",
        ],
    },
    {
        "id": "10000000-0000-4000-8000-000000000002",
        "albumName": "Family",
        "thumbnail": "20000000-0000-4000-8000-000000000004",
        "startDate": "2025-01-01T00:00:00.000Z",
        "assets": [
            "20000000-0000-4000-8000-000000000004",
            "20000000-0000-4000-8000-000000000005",
        ],
    },
]

EXIF = {
    "20000000-0000-4000-8000-000000000001": ("Lisbon", "Lisboa", "Portugal"),
    "20000000-0000-4000-8000-000000000002": ("Porto", "Porto", "Portugal"),
    "20000000-0000-4000-8000-000000000003": ("Sintra", "Lisboa", "Portugal"),
    "20000000-0000-4000-8000-000000000004": ("Rome", "Lazio", "Italy"),
    "20000000-0000-4000-8000-000000000005": ("Milan", "Lombardy", "Italy"),
}

TIMESTAMP = "2025-06-01T10:15:00.000Z"


def user_dto() -> dict:
    return {
        "id": OWNER_ID,
        "email": "mock@example.com",
        "name": "Mock User",
        "profileImagePath": "",
        "avatarColor": "primary",
        "profileChangedAt": "2025-01-01T00:00:00.000Z",
    }


def album_dto(album: dict) -> dict:
    return {
        "id": album["id"],
        "albumName": album["albumName"],
        "description": "",
        "albumThumbnailAssetId": album["thumbnail"],
        "createdAt": "2025-01-01T00:00:00.000Z",
        "updatedAt": TIMESTAMP,
        "startDate": album["startDate"],
        "assetCount": len(album["assets"]),
        "shared": False,
        "hasSharedLink": False,
        "isActivityEnabled": True,
        "owner": user_dto(),
        "albumUsers": [{"role": "owner", "user": user_dto()}],
    }


def asset_dto(asset_id: str, with_exif: bool) -> dict:
    dto = {
        "id": asset_id,
        "type": "IMAGE",
        "originalPath": f"/data/{asset_id}.jpg",
        "originalFileName": f"{asset_id}.jpg",
        "deviceAssetId": asset_id,
        "deviceId": "mock-device",
        "ownerId": OWNER_ID,
        "checksum": "bW9ja2NoZWNrc3Vt",
        "thumbhash": "bW9ja3RodW1i",
        "duration": None,
        "fileCreatedAt": TIMESTAMP,
        "fileModifiedAt": TIMESTAMP,
        "localDateTime": TIMESTAMP,
        "createdAt": TIMESTAMP,
        "updatedAt": TIMESTAMP,
        "isArchived": False,
        "isEdited": False,
        "isFavorite": False,
        "isOffline": False,
        "isTrashed": False,
        "hasMetadata": True,
        "visibility": "timeline",
        "width": 1920,
        "height": 1080,
    }
    if with_exif:
        city, state, country = EXIF.get(asset_id, (None, None, None))
        dto["exifInfo"] = {
            "dateTimeOriginal": TIMESTAMP,
            "city": city,
            "state": state,
            "country": country,
        }
    return dto


def find_album(album_id: str) -> dict | None:
    return next((a for a in ALBUMS if a["id"] == album_id), None)


@app.get("/api/server/version")
def server_version():
    return {"major": 3, "minor": 0, "patch": 2, "prerelease": None}


@app.get("/api/albums")
def get_albums(shared: bool = False):
    if shared:
        return []
    return [album_dto(a) for a in ALBUMS]


@app.get("/api/albums/{album_id}")
def get_album(album_id: str):
    album = find_album(album_id)
    if album is None:
        return Response(status_code=404)
    return album_dto(album)


@app.post("/api/search/metadata")
async def search_metadata(request: Request):
    body = await request.json()
    album_ids = body.get("albumIds", [])
    items = []
    for album_id in album_ids:
        album = find_album(album_id)
        if album:
            # The real search response omits exifInfo; the app fetches it
            # per-asset via GET /api/assets/{id}.
            items += [asset_dto(a, with_exif=False) for a in album["assets"]]
    return {
        "assets": {
            "total": len(items),
            "count": len(items),
            "items": items,
            "nextPage": None,
            "facets": [],
        },
        "albums": {"total": 0, "count": 0, "items": [], "facets": [], "nextPage": None},
    }


@app.get("/api/assets/{asset_id}")
def get_asset(asset_id: str):
    return asset_dto(asset_id, with_exif=True)


@app.get("/api/assets/{asset_id}/thumbnail")
def get_thumbnail(asset_id: str, size: str = "thumbnail"):
    return Response(content=render_image(asset_id, size), media_type="image/jpeg")


@app.post("/api/auth/login")
async def login():
    return {
        "accessToken": "mock-session-token",
        "userId": OWNER_ID,
        "userEmail": "mock@example.com",
        "name": "Mock User",
        "isAdmin": True,
        "isOnboarded": True,
        "profileImagePath": "",
        "shouldChangePassword": False,
    }


def render_image(asset_id: str, size: str) -> bytes:
    width, height = (1920, 1080) if size == "fullsize" else (640, 360)
    digest = hashlib.sha256(asset_id.encode()).digest()
    color = (digest[0], digest[1], digest[2])

    image = Image.new("RGB", (width, height), color)
    draw = ImageDraw.Draw(image)
    draw.text((width // 2 - 60, height // 2 - 10), asset_id[-12:], fill="white")

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG")
    return buffer.getvalue()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8123)
    args = parser.parse_args()
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")
