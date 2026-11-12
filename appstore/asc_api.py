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
REVIEW_DETAIL_ID = "263cfdd4-5705-4efe-bb10-dabba46679eb"
DEMO_EMAIL = "jcebertowski0+aogreview@gmail.com"
DEMO_PASSWORD = "ArmorReview2026!"
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


def verify():
    """Read-only: confirm screenshots, privacy URL, review detail, and the exact
    validation errors that still block a review submission."""
    status, payload = req("GET", f"/v1/appStoreVersionLocalizations/{LOCALIZATION_ID}/appScreenshotSets")
    sets = payload.get("data", []) if isinstance(payload, dict) else []
    print(f"screenshot sets: {len(sets)}")
    for st in sets:
        print(f"  set {st['id']} type={st['attributes']['screenshotDisplayType']}")
        s2, p2 = req("GET", f"/v1/appScreenshotSets/{st['id']}/appScreenshots")
        for shot in (p2.get("data", []) if isinstance(p2, dict) else []):
            a = shot["attributes"]
            state = a.get("assetDeliveryState") or {}
            print(f"    {a['fileName']} {a['fileSize']}B state={state.get('state')} errors={state.get('errors')}")
    s3, p3 = req("GET", f"/v1/appInfos/{APP_INFO_ID}/appInfoLocalizations")
    for loc in (p3.get("data", []) if isinstance(p3, dict) else []):
        print(f"appInfoLocalization {loc['attributes']['locale']} privacyPolicyUrl={loc['attributes'].get('privacyPolicyUrl')}")
    s4, p4 = req("GET", f"/v1/appStoreVersions/{VERSION_ID}/appStoreReviewDetail")
    print(f"review detail: {json.dumps(p4)[:300]}")
    sid = "a77fbd46-0437-4b5f-93fa-7e67731cf99e"
    s5, p5 = req("POST", "/v1/reviewSubmissionItems", {
        "data": {"type": "reviewSubmissionItems",
                 "relationships": {
                     "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                     "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}}}}})
    print(f"add version to submission -> {s5}")
    print(json.dumps(p5, indent=1)[:3000] if isinstance(p5, dict) else p5[:2000])


def review_detail():
    """Create the App Review contact record, then re-check submission validation."""
    body = {"data": {"type": "appStoreReviewDetails",
                     "attributes": {"contactFirstName": "Jacob",
                                    "contactLastName": "Ebertowski",
                                    "contactPhone": "+17015186261",
                                    "contactEmail": "jcebertowski0@gmail.com",
                                    "demoAccountRequired": True},
                     "relationships": {"appStoreVersion": {
                         "data": {"type": "appStoreVersions", "id": VERSION_ID}}}}}
    status, payload = req("POST", "/v1/appStoreReviewDetails", body)
    print(f"create review detail -> {status}")
    print(json.dumps(payload, indent=1)[:2000] if isinstance(payload, dict) else payload[:1500])
    sid = "a77fbd46-0437-4b5f-93fa-7e67731cf99e"
    s2, p2 = req("POST", "/v1/reviewSubmissionItems", {
        "data": {"type": "reviewSubmissionItems",
                 "relationships": {
                     "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                     "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}}}}})
    print(f"add version to submission -> {s2}")
    print(json.dumps(p2, indent=1)[:2500] if isinstance(p2, dict) else p2[:1500])


def probe_privacy():
    """Find out whether Apple exposes the App Privacy (data usage) answers via API."""
    candidates = [
        "/v1/appDataUsages",
        "/v1/appDataUsageCategories",
        f"/v1/appInfos/{APP_INFO_ID}/appDataUsages",
        f"/v1/apps/{APP_ID}/appDataUsagePublishments",
        "/v1/appDataUsagePublishments",
        f"/v1/apps/{APP_ID}/appEncryptionDeclarations",
        "/v1/appDataUsages?filter%5Bapp%5D=6821792871",
    ]
    for path in candidates:
        status, payload = req("GET", path)
        body = payload if isinstance(payload, str) else json.dumps(payload)
        print(f"[{status}] GET {path}")
        print("    " + body[:400].replace("\n", " "), flush=True)


def fix_age():
    """Correct the two age-rating answers now that Spartan RoundTable is confirmed
    to be a user message board (postRoundTableMessage, content/message_type/prayers)."""
    status, payload = req("GET", f"/v1/appInfos/{APP_INFO_ID}/ageRatingDeclaration")
    decl_id = payload["data"]["id"]
    attrs = dict(AGE_RATING)
    attrs["userGeneratedContent"] = True
    attrs["messagingAndChat"] = True
    status, payload = req("PATCH", f"/v1/ageRatingDeclarations/{decl_id}",
                          {"data": {"type": "ageRatingDeclarations", "id": decl_id,
                                    "attributes": attrs}})
    print(f"age rating PATCH -> {status}")
    print(json.dumps(payload)[:900] if isinstance(payload, dict) else payload[:600])


def submit_demo():
    """Fill the dedicated review login, then submit version 2.0 for review."""
    body = {"data": {"type": "appStoreReviewDetails", "id": REVIEW_DETAIL_ID, "attributes": {
        "demoAccountRequired": True,
        "demoAccountName": DEMO_EMAIL,
        "demoAccountPassword": DEMO_PASSWORD,
        "notes": "Sign in with the demo account above. The app opens an 18+ age confirmation; accept it to continue. The account starts empty, so the morning briefing, lift history and budget fill in as you add an event, a meal or a set; RoundTable is open to post to."}}}
    status, payload = req("PATCH", "/v1/appStoreReviewDetails/" + REVIEW_DETAIL_ID, body)
    print("review detail PATCH -> %s" % status)
    print(str(payload)[:400])

    status, payload = req("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    print("review submission -> %s" % status)
    sid = payload.get("data", {}).get("id") if isinstance(payload, dict) else None
    print("SID", sid)
    if not sid:
        print(str(payload)[:700]); return
    status, payload = req("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}}, "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}}}}})
    print("add item -> %s" % status)
    print(str(payload)[:800])
    status, payload = req("PATCH", "/v1/reviewSubmissions/" + sid, {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
    print("confirm -> %s" % status)
    print(str(payload)[:700])


def builds():
    """Read-only: newest TestFlight / App Store builds for the app."""
    st, payload = req("GET", f"/v1/builds?filter%5Bapp%5D={APP_ID}&sort=-uploadedDate&limit=5")
    if not isinstance(payload, dict) or "data" not in payload:
        print("builds GET ->", st, str(payload)[:300]); return
    for b in payload["data"]:
        a = b["attributes"]
        print(f"build {a.get('version')} | {a.get('processingState')} | expires {a.get('expirationDate')} | uploaded {a.get('uploadedDate')} | audience {a.get('buildAudienceType')}")
    for b in payload["data"][:3]:
        st2, d = req("GET", f"/v1/builds/{b['id']}/buildBetaDetail")
        if isinstance(d, dict) and d.get("data"):
            at = d["data"]["attributes"]
            print(f"  beta({b['attributes'].get('version')}): internal={at.get('internalBuildState')} external={at.get('externalBuildState')} autoNotify={at.get('autoNotifyEnabled')}")


def status():
    """Read-only: is 2.0 approved / live, and what is the newest TestFlight build?"""
    st, v = req("GET", f"/v1/appStoreVersions/{VERSION_ID}")
    if isinstance(v, dict) and v.get("data"):
        a = v["data"]["attributes"]
        print(f"version {a.get('versionString')}: appStoreState={a.get('appStoreState')} appVersionState={a.get('appVersionState')} created={a.get('createdDate')}")
    else:
        print("version GET ->", st, str(v)[:200])
    st, r = req("GET", f"/v1/apps/{APP_ID}/reviewSubmissions?limit=5")
    if isinstance(r, dict) and r.get("data") is not None:
        for x in r["data"]:
            print(f"submission {x['id']}: state={x['attributes'].get('state')} submitted={x['attributes'].get('submittedDate')}")
    else:
        print("submissions ->", st, str(r)[:200])
    st, a = req("GET", f"/v1/apps/{APP_ID}/appAvailabilityV2")
    print("availability ->", st)
    builds()


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "discover"
    {"discover": lambda: None, "setup": setup, "finish": finish, "verify": verify, "review_detail": review_detail, "probe_privacy": probe_privacy, "fix_age": fix_age, "submit_demo": submit_demo}[mode]()
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
