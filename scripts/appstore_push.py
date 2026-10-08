# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt>=2.8", "cryptography>=42", "requests>=2.31"]
# ///
"""Push Giant Buddy App Store metadata and screenshots to App Store Connect.

Reads docs/appstore/ and updates the editable app info (name, subtitle,
privacy URL, categories), the iOS App Store version (copyright), its en-US
localization (description, keywords, promotional text, support URL),
App Review details and the iPhone 6.9" and Apple Watch Ultra screenshots.

Credentials (never commit the .p8):
  ASC_ISSUER_ID  Issuer ID (App Store Connect > Users and Access > Integrations)
  ASC_KEY_ID     Key ID of the API key
  ASC_KEY_PATH   Path to AuthKey_<KEY_ID>.p8, kept outside the repo

Usage:
  uv run scripts/appstore_push.py --dry-run
  uv run scripts/appstore_push.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import jwt
import requests

BASE_URL = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "dk.hilli.GiantLogger"
LOCALE = "en-US"
ROOT = Path(__file__).resolve().parent.parent
APPSTORE_DIR = ROOT / "docs" / "appstore"
METADATA_DIR = APPSTORE_DIR / "metadata" / LOCALE
SCREENSHOT_DIR = APPSTORE_DIR / "screenshots"
# Screenshot folder -> App Store Connect display type
SCREENSHOT_SETS = {
    "iphone": "APP_IPHONE_67",  # 6.9" iPhone slot; accepts 1320x2868
    "watch": "APP_WATCH_ULTRA",  # Apple Watch Ultra slot; accepts 422x514
}
REVIEW_CONTACT = APPSTORE_DIR / "review_contact.local.json"

METADATA_FIELDS = (
    "name",
    "subtitle",
    "keywords",
    "promotional_text",
    "description",
    "review_notes",
    "support_url",
    "marketing_url",
    "privacy_url",
    "copyright",
    "primary_category",
    "secondary_category",
)
LIMITS = {
    "name": 30,
    "subtitle": 30,
    "keywords": 100,
    "promotional_text": 170,
    "description": 4000,
    "review_notes": 4000,
}
REQUIRED = ("name", "description", "keywords", "support_url", "privacy_url")
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}


class ASCError(RuntimeError):
    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


def load_metadata() -> dict[str, str]:
    meta = {}
    for field in METADATA_FIELDS:
        path = METADATA_DIR / f"{field}.txt"
        meta[field] = path.read_text(encoding="utf-8").strip() if path.exists() else ""
    errors = [
        f"{field}.txt is {len(meta[field])} chars (max {limit})"
        for field, limit in LIMITS.items()
        if len(meta[field]) > limit
    ]
    errors += [f"{field}.txt is missing or empty" for field in REQUIRED if not meta[field]]
    if errors:
        raise SystemExit("Metadata validation failed:\n  " + "\n  ".join(errors))
    return meta


def load_review_contact() -> dict[str, str] | None:
    if not REVIEW_CONTACT.exists():
        return None
    data = json.loads(REVIEW_CONTACT.read_text(encoding="utf-8"))
    keys = ("contactFirstName", "contactLastName", "contactEmail", "contactPhone")
    missing = [key for key in keys if not data.get(key)]
    if missing:
        raise SystemExit(f"{REVIEW_CONTACT.name} is missing: {', '.join(missing)}")
    return {key: data[key] for key in keys}


class ASC:
    def __init__(self, issuer_id: str, key_id: str, key_path: Path, dry_run: bool):
        self.issuer_id = issuer_id
        self.key_id = key_id
        self.private_key = key_path.read_text(encoding="utf-8")
        self.dry_run = dry_run
        self.session = requests.Session()
        self._token = ""
        self._token_exp = 0.0

    def _auth(self) -> str:
        now = time.time()
        if now > self._token_exp - 60:
            self._token_exp = now + 15 * 60
            self._token = jwt.encode(
                {"iss": self.issuer_id, "iat": int(now), "exp": int(self._token_exp), "aud": "appstoreconnect-v1"},
                self.private_key,
                algorithm="ES256",
                headers={"kid": self.key_id, "typ": "JWT"},
            )
        return self._token

    def request(self, method: str, path: str, *, params: dict | None = None, body: dict | None = None) -> dict | None:
        if method != "GET" and self.dry_run:
            attrs = (body or {}).get("data", {}).get("attributes", {})
            print(f"    [dry-run] {method} {path} {json.dumps(attrs, ensure_ascii=False)[:160]}")
            return None
        resp = self.session.request(
            method,
            f"{BASE_URL}{path}",
            params=params,
            json=body,
            headers={"Authorization": f"Bearer {self._auth()}"},
            timeout=60,
        )
        if resp.status_code >= 400:
            raise ASCError(f"{method} {path} -> {resp.status_code}\n{resp.text}", resp.status_code)
        return resp.json() if resp.content else None

    def get(self, path: str, **params: str) -> dict:
        return self.request("GET", path, params=params or None) or {}

    def create(self, type_: str, attributes: dict, relationships: dict) -> dict | None:
        body = {"data": {"type": type_, "attributes": attributes, "relationships": relationships}}
        result = self.request("POST", f"/v1/{type_}", body=body)
        return result["data"] if result else None

    def update(self, type_: str, id_: str, attributes: dict | None = None, relationships: dict | None = None) -> None:
        data: dict = {"type": type_, "id": id_}
        if attributes:
            data["attributes"] = attributes
        if relationships:
            data["relationships"] = relationships
        self.request("PATCH", f"/v1/{type_}/{id_}", body={"data": data})


def rel(type_: str, id_: str) -> dict:
    return {"data": {"type": type_, "id": id_}}


def state_of(resource: dict) -> str:
    attrs = resource["attributes"]
    return attrs.get("state") or attrs.get("appVersionState") or attrs.get("appStoreState") or ""


def find_app(api: ASC) -> dict:
    apps = api.get("/v1/apps", **{"filter[bundleId]": BUNDLE_ID}).get("data", [])
    if not apps:
        raise SystemExit(f"No App Store Connect app found for bundle ID {BUNDLE_ID}")
    app = apps[0]
    print(f"App: {app['attributes']['name']} ({app['id']})")
    return app


def push_app_info(api: ASC, app_id: str, meta: dict[str, str]) -> None:
    infos = api.get(f"/v1/apps/{app_id}/appInfos")["data"]
    info = next((item for item in infos if state_of(item) in EDITABLE_STATES), None)
    if info is None:
        raise SystemExit("No editable app info (states: " + ", ".join(state_of(i) for i in infos) + ")")
    print(f"App info {info['id']} ({state_of(info)})")

    attributes = {"name": meta["name"], "subtitle": meta["subtitle"] or None, "privacyPolicyUrl": meta["privacy_url"]}
    locs = api.get(f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]
    loc = next((item for item in locs if item["attributes"]["locale"] == LOCALE), None)
    print(f"  {LOCALE}: name, subtitle, privacy policy URL")
    if loc:
        api.update("appInfoLocalizations", loc["id"], attributes)
    else:
        api.create("appInfoLocalizations", {"locale": LOCALE, **attributes}, {"appInfo": rel("appInfos", info["id"])})

    relationships = {}
    if meta["primary_category"]:
        relationships["primaryCategory"] = rel("appCategories", meta["primary_category"])
    if meta["secondary_category"]:
        relationships["secondaryCategory"] = rel("appCategories", meta["secondary_category"])
    if relationships:
        print(f"  categories: {meta['primary_category']} / {meta['secondary_category'] or '-'}")
        api.update("appInfos", info["id"], relationships=relationships)


def get_or_create_version(api: ASC, app_id: str, version: str, meta: dict[str, str]) -> str | None:
    versions = api.get(
        f"/v1/apps/{app_id}/appStoreVersions",
        **{"filter[platform]": "IOS", "filter[versionString]": version},
    )["data"]
    attributes = {"copyright": meta["copyright"] or None}
    if versions:
        ver = versions[0]
        if state_of(ver) not in EDITABLE_STATES:
            raise SystemExit(f"Version {version} is {state_of(ver)} and can't be edited")
        print(f"Version {version} ({ver['id']}, {state_of(ver)})")
        print("  copyright")
        api.update("appStoreVersions", ver["id"], attributes)
        return ver["id"]
    print(f"Version {version}: creating")
    created = api.create(
        "appStoreVersions",
        {"platform": "IOS", "versionString": version, **attributes},
        {"app": rel("apps", app_id)},
    )
    return created["id"] if created else None


def push_version_localization(api: ASC, version_id: str, meta: dict[str, str]) -> str | None:
    attributes = {
        "description": meta["description"],
        "keywords": meta["keywords"],
        "promotionalText": meta["promotional_text"] or None,
        "supportUrl": meta["support_url"],
        "marketingUrl": meta["marketing_url"] or None,
    }
    locs = api.get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
    loc = next((item for item in locs if item["attributes"]["locale"] == LOCALE), None)
    print(f"  {LOCALE}: description, keywords, promotional text, support URL")
    if loc:
        api.update("appStoreVersionLocalizations", loc["id"], attributes)
        return loc["id"]
    created = api.create(
        "appStoreVersionLocalizations",
        {"locale": LOCALE, **attributes},
        {"appStoreVersion": rel("appStoreVersions", version_id)},
    )
    return created["id"] if created else None


def push_review_details(api: ASC, version_id: str, meta: dict[str, str], contact: dict[str, str] | None) -> None:
    if contact is None:
        print(f"  review details: skipped ({REVIEW_CONTACT.name} not found)")
        return
    attributes = {**contact, "notes": meta["review_notes"] or None, "demoAccountRequired": False}
    try:
        existing = api.get(f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail").get("data")
    except ASCError as err:
        if err.status != 404:
            raise
        existing = None
    print("  review details: contact + notes")
    if existing:
        api.update("appStoreReviewDetails", existing["id"], attributes)
    else:
        api.create("appStoreReviewDetails", attributes, {"appStoreVersion": rel("appStoreVersions", version_id)})


def upload_screenshot(api: ASC, set_id: str, path: Path) -> None:
    data = path.read_bytes()
    created = api.create(
        "appScreenshots",
        {"fileName": path.name, "fileSize": len(data)},
        {"appScreenshotSet": rel("appScreenshotSets", set_id)},
    )
    if created is None:
        return
    for op in created["attributes"]["uploadOperations"]:
        chunk = data[op["offset"] : op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        resp = requests.request(op["method"], op["url"], data=chunk, headers=headers, timeout=120)
        if resp.status_code >= 400:
            raise ASCError(f"Upload of {path.name} failed: {resp.status_code} {resp.text}", resp.status_code)
    api.update("appScreenshots", created["id"], {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})

    for _ in range(30):
        attrs = api.get(f"/v1/appScreenshots/{created['id']}")["data"]["attributes"]
        delivery = attrs.get("assetDeliveryState") or {}
        if delivery.get("state") == "COMPLETE":
            return
        if delivery.get("state") == "FAILED":
            raise ASCError(f"{path.name} processing failed: {delivery.get('errors')}")
        time.sleep(2)
    print(f"    {path.name}: still processing, check App Store Connect")


def push_screenshot_set(api: ASC, localization_id: str, sets: list[dict], folder: str, display_type: str) -> None:
    files = sorted((SCREENSHOT_DIR / folder).glob("*.png"))
    if not files:
        print(f"  {folder} screenshots: none found, skipped")
        return
    shot_set = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == display_type), None)
    if shot_set is None:
        shot_set = api.create(
            "appScreenshotSets",
            {"screenshotDisplayType": display_type},
            {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", localization_id)},
        )
        if shot_set is None:
            print(f"  {folder} screenshots: would upload {len(files)} to a new {display_type} set")
            return
    else:
        existing = api.get(f"/v1/appScreenshotSets/{shot_set['id']}/appScreenshots")["data"]
        local = [hashlib.md5(path.read_bytes()).hexdigest() for path in files]
        if [shot["attributes"].get("sourceFileChecksum") for shot in existing] == local:
            print(f"  {folder} screenshots: unchanged")
            return
        if existing:
            print(f"  {folder} screenshots: removing {len(existing)} existing")
        for shot in existing:
            api.request("DELETE", f"/v1/appScreenshots/{shot['id']}")
    for path in files:
        print(f"  {folder} screenshot: {path.name}")
        upload_screenshot(api, shot_set["id"], path)


def push_screenshots(api: ASC, localization_id: str) -> None:
    sets = api.get(f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")["data"]
    for folder, display_type in SCREENSHOT_SETS.items():
        push_screenshot_set(api, localization_id, sets, folder, display_type)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="read from App Store Connect but change nothing")
    parser.add_argument("--version", default="1.0", help="App Store version string (default: 1.0)")
    parser.add_argument("--skip-screenshots", action="store_true", help="leave screenshots untouched")
    args = parser.parse_args()

    meta = load_metadata()
    contact = load_review_contact()
    print("Local metadata OK")

    env = {key: os.environ.get(key, "") for key in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_KEY_PATH")}
    missing = [key for key, value in env.items() if not value]
    if missing:
        raise SystemExit(f"Missing environment variables: {', '.join(missing)} (see docs/appstore/checklist.md)")
    key_path = Path(env["ASC_KEY_PATH"]).expanduser()
    if not key_path.is_file():
        raise SystemExit(f"ASC_KEY_PATH not found: {key_path}")
    if ROOT in key_path.resolve().parents:
        print("WARNING: the .p8 key is inside the repo; keep it outside so it can't be committed", file=sys.stderr)

    api = ASC(env["ASC_ISSUER_ID"], env["ASC_KEY_ID"], key_path, args.dry_run)
    try:
        app = find_app(api)
        push_app_info(api, app["id"], meta)
        version_id = get_or_create_version(api, app["id"], args.version, meta)
        if version_id is None:
            print("Dry run: version doesn't exist yet, skipping version-level changes")
            return
        localization_id = push_version_localization(api, version_id, meta)
        push_review_details(api, version_id, meta, contact)
        if localization_id and not args.skip_screenshots:
            push_screenshots(api, localization_id)
    except ASCError as err:
        raise SystemExit(f"App Store Connect API error: {err}") from None
    print("Done" + (" (dry run, nothing changed)" if args.dry_run else ""))


if __name__ == "__main__":
    main()
