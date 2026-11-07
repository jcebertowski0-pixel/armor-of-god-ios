#!/usr/bin/env python3
"""Read/write App Store Connect through the raw REST API.

Runs inside the Codemagic "aog-asc-tools" workflow, where the "Codemagic"
App Store Connect key is available as APP_STORE_CONNECT_ISSUER_ID /
APP_STORE_CONNECT_KEY_IDENTIFIER / APP_STORE_CONNECT_PRIVATE_KEY.
The Codemagic CLI cannot reach app-level, pricing or screenshot endpoints, so
this script talks to api.appstoreconnect.apple.com directly.

Usage: python3 appstore/asc_api.py <mode>
  discover  - read-only dump
  setup     - screenshots, copyright, content rights, category, privacy URL, price
"""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

APP_ID = "6821792871"
VERSION_ID = "7f03af6f-588e-4c73-b6e1-edc337727f4c"
LOCALIZATION_ID = "03f3de21-af33-4448-909f-b3dc5563cc4f"
APP_INFO_ID = "15bd421e-a6dc-4fad-ac2a-e56d038f6f31"
BASE = "https://api.appstoreconnect.apple.com"
SHOTS = [
    "appstore/screenshots/01-dashboard.jpg",
    "appstore/screenshots/02-training-modules.jpg",
    "appstore/screenshots/03-morning-briefing.jpg",
]
PRIVACY_URL = "https://divine-armor-path.base44.app/PrivacyPolicy"
COPYRIGHT = "2026 Free Bird Applications"


def _key():
    raw = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY", "")
    if "PRIVATE KEY" in raw:
        return raw
    for path in (raw,
                 os.path.expanduser("~/.appstoreconnect/private_keys/"
                                    f"AuthKey_{os.environ.get('APP_STORE_CONNECT_KEY_IDENTIFIER', '')}.p8")):
        if path and os.path.exists(path):
            with open(path) as fh:
                return fh.read()
    raise SystemExit("no ASC private key in environment")


def token():
    import jwt
    return jwt.encode(
        {
            "iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"],
            "iat": int(time.time()),
            "exp": int(time.time()) + 900,
            "aud": "appstoreconnect-v1",
        },
        _key(),
        algorithm="ES256",
        headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]},
    )


_TOKEN = None


def req(method, path, body=None):
    global _TOKEN
    if _TOKEN is None:
        _TOKEN = token()
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", "Bearer " + _TOKEN)
    if data:
        r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=120) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


def call(label, method, path, body=None, quiet=False):
    status, payload = req(method, path, body)
    ok = 200 <= status < 300
    print(f"{'OK ' if ok else 'ERR'} [{status}] {method} {path}", flush=True)
    if not ok or not quiet:
        text = payload if isinstance(payload, str) else json.dumps(payload)
        print("    " + text[:900].replace("\n", "\n    "), flush=True)
    return status, payload


def screenshots():
    status, payload = call("sets", "GET",
                           f"/v1/appStoreVersionLocalizations/{LOCALIZATION_ID}/appScreenshotSets")
    sets = payload.get("data", []) if isinstance(payload, dict) else []
    set_id = None
    for s in sets:
        if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67":
            set_id = s["id"]
    if not set_id:
        status, payload = call("create set", "POST", "/v1/appScreenshotSets", {
            "data": {"type": "appScreenshotSets",
                     "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
                     "relationships": {"appStoreVersionLocalization": {
                         "data": {"type": "appStoreVersionLocalizations",
                                  "id": LOCALIZATION_ID}}}}})
        if status >= 300:
            return
        set_id = payload["data"]["id"]
    print(f"    screenshot set {set_id}", flush=True)

    for path in SHOTS:
        with open(path, "rb") as fh:
            blob = fh.read()
        name = os.path.basename(path)
        status, payload = call(f"reserve {name}", "POST", "/v1/appScreenshots", {
            "data": {"type": "appScreenshots",
                     "attributes": {"fileName": name, "fileSize": len(blob)},
                     "relationships": {"appScreenshotSet": {
                         "data": {"type": "appScreenshotSets", "id": set_id}}}}})
        if status >= 300:
            continue
        shot_id = payload["data"]["id"]
        for op in payload["data"]["attributes"].get("uploadOperations", []):
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            chunk = blob[op.get("offset", 0):op.get("offset", 0) + op["length"]]
            r = urllib.request.Request(op["url"], data=chunk, method=op["method"])
            for k, v in headers.items():
                r.add_header(k, v)
            try:
                with urllib.request.urlopen(r, timeout=180) as resp:
                    print(f"    upload {name} chunk -> {resp.status}", flush=True)
            except urllib.error.HTTPError as exc:
                print(f"    upload {name} chunk FAILED {exc.code} {exc.read()[:200]}", flush=True)
        checksum = hashlib.md5(blob).hexdigest()
        call(f"commit {name}", "PATCH", f"/v1/appScreenshots/{shot_id}", {
            "data": {"type": "appScreenshots", "id": shot_id,
                     "attributes": {"uploaded": True, "sourceFileChecksum": checksum}}})


def version_and_app():
    call("copyright", "PATCH", f"/v1/appStoreVersions/{VERSION_ID}", {
        "data": {"type": "appStoreVersions", "id": VERSION_ID,
                 "attributes": {"copyright": COPYRIGHT}}})
    call("content rights", "PATCH", f"/v1/apps/{APP_ID}", {
        "data": {"type": "apps", "id": APP_ID,
                 "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})


def app_info():
    call("primary category", "PATCH", f"/v1/appInfos/{APP_INFO_ID}", {
        "data": {"type": "appInfos", "id": APP_INFO_ID,
                 "relationships": {"primaryCategory": {
                     "data": {"type": "appCategories", "id": "HEALTH_AND_FITNESS"}}}}})
    status, payload = call("info localizations", "GET",
                           f"/v1/appInfos/{APP_INFO_ID}/appInfoLocalizations")
    locs = payload.get("data", []) if isinstance(payload, dict) else []
    for loc in locs:
        if loc["attributes"].get("locale") == "en-US":
            lid = loc["id"]
            print(f"    appInfoLocalization en-US = {lid} "
                  f"privacyPolicyUrl={loc['attributes'].get('privacyPolicyUrl')}", flush=True)
            call("privacy url", "PATCH", f"/v1/appInfoLocalizations/{lid}", {
                "data": {"type": "appInfoLocalizations", "id": lid,
                         "attributes": {"privacyPolicyUrl": PRIVACY_URL}}})


def age_rating():
    status, payload = call("age rating", "GET",
                           f"/v1/appInfos/{APP_INFO_ID}/ageRatingDeclaration", quiet=True)
    if status >= 300 or not isinstance(payload, dict) or not payload.get("data"):
        print("    no age rating declaration yet", flush=True)
        return
    decl = payload["data"]
    print("    current:", json.dumps(decl["attributes"])[:800], flush=True)
    for value in (False, "NONE"):
        status, _ = req("PATCH", f"/v1/ageRatingDeclarations/{decl['id']}", {
            "data": {"type": "ageRatingDeclarations", "id": decl["id"],
                     "attributes": {"socialMedia": value,
                                    "medicalOrTreatmentInformation": value}}})
        print(f"    patch with {value!r} -> {status}", flush=True)
        if status < 300:
            return


def pricing():
    status, payload = call("price points", "GET",
                           f"/v1/apps/{APP_ID}/appPricePoints?filter[territory]=USA&limit=200",
                           quiet=True)
    if status >= 300:
        return
    free = None
    for p in payload.get("data", []):
        if p["attributes"].get("customerPrice") in ("0.0", "0", "0.00"):
            free = p["id"]
            break
    print(f"    free price point: {free}", flush=True)
    if not free:
        return
    call("price schedule", "POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules",
                 "relationships": {
                     "app": {"data": {"type": "apps", "id": APP_ID}},
                     "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                     "manualPrices": {"data": [{"type": "appPrices", "id": "${p1}"}]}}},
        "included": [{"type": "appPrices", "id": "${p1}",
                      "relationships": {
                          "appPricePoint": {"data": {"type": "appPricePoints", "id": free}},
                          "territory": {"data": {"type": "territories", "id": "USA"}}}}]})


def setup():
    version_and_app()
    app_info()
    age_rating()
    pricing()
    screenshots()


AGE_RATING = {
    "advertising": False,
    "alcoholTobaccoOrDrugUseOrReferences": "NONE",
    "contests": "NONE",
    "gambling": False,
    "gamblingSimulated": "NONE",
    "gunsOrOtherWeapons": "NONE",
    "healthOrWellnessTopics": True,
    "lootBox": False,
    "medicalOrTreatmentInformation": "NONE",
    "messagingAndChat": False,
    "parentalControls": False,
    "profanityOrCrudeHumor": "NONE",
    "ageAssurance": False,
    "sexualContentGraphicAndNudity": "NONE",
    "sexualContentOrNudity": "NONE",
    "socialMedia": False,
    "socialMediaAgeRestricted": False,
    "horrorOrFearThemes": "NONE",
    "matureOrSuggestiveThemes": "NONE",
    "unrestrictedWebAccess": False,
    "userGeneratedContent": False,
    "violenceCartoonOrFantasy": "NONE",
    "violenceRealistic": "NONE",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
}


def age_rating_full():
    status, payload = req("GET", f"/v1/appInfos/{APP_INFO_ID}/ageRatingDeclaration")
    if status >= 300 or not payload.get("data"):
        print("no declaration", status, payload)
        return
    decl_id = payload["data"]["id"]
    status, payload = req("PATCH", f"/v1/ageRatingDeclarations/{decl_id}",
                          {"data": {"type": "ageRatingDeclarations", "id": decl_id,
                                    "attributes": AGE_RATING}})
    print(f"age rating PATCH -> {status}")
    print(json.dumps(payload)[:1500])


def finish():
    age_rating_full()
    status, payload = req("GET", f"/v1/apps/{APP_ID}/reviewSubmissions?limit=20")
    for sub in (payload.get("data", []) if isinstance(payload, dict) else []):
        if sub["attributes"].get("state") in ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW"):
            call("cancel old submission", "DELETE", f"/v1/reviewSubmissions/{sub['id']}", quiet=True)
    status, payload = call("new submission", "POST", "/v1/reviewSubmissions", {
        "data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                 "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    if status >= 300:
        return
    sid = payload["data"]["id"]
    call("add 2.0 item", "POST", "/v1/reviewSubmissionItems", {
        "data": {"type": "reviewSubmissionItems",
                 "relationships": {
                     "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                     "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}}}}})
    call("submit", "PATCH", f"/v1/reviewSubmissions/{sid}", {
        "data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "discover"
    {"discover": lambda: None, "setup": setup, "finish": finish}[mode]()
    if mode == "discover":
        for label, path in [
            ("app", f"/v1/apps/{APP_ID}"),
            ("app infos", f"/v1/apps/{APP_ID}/appInfos"),
            ("screenshot sets", f"/v1/appStoreVersionLocalizations/{LOCALIZATION_ID}/appScreenshotSets"),
            ("price schedule", f"/v1/apps/{APP_ID}/appPriceSchedule"),
            ("review detail", f"/v1/appStoreVersions/{VERSION_ID}/appStoreReviewDetail"),
        ]:
            status, payload = req("GET", path)
            print(f"\n=== {label} [{status}]", json.dumps(payload)[:1200] if isinstance(payload, dict) else payload[:400])


if __name__ == "__main__":
    main()
