#!/usr/bin/env python3
"""Read/write App Store Connect through the raw REST API.

Runs inside the Codemagic "aog-asc-tools" workflow, where the "Codemagic"
App Store Connect key is available as APP_STORE_CONNECT_ISSUER_ID /
APP_STORE_CONNECT_KEY_IDENTIFIER / APP_STORE_CONNECT_PRIVATE_KEY.
The Codemagic CLI cannot reach app-level and screenshot endpoints, so this
script talks to api.appstoreconnect.apple.com directly.

Usage: python3 appstore/asc_api.py <mode>
  discover  - read-only dump of everything needed to finish the listing
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

APP_ID = "6821792871"
VERSION_ID = "7f03af6f-588e-4c73-b6e1-edc337727f4c"
LOCALIZATION_ID = "03f3de21-af33-4448-909f-b3dc5563cc4f"
BUNDLE_ID = "com.freebirdapps.armorofgod"
BASE = "https://api.appstoreconnect.apple.com"


def _key():
    raw = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY", "")
    if raw.startswith("-----BEGIN") or "PRIVATE KEY" in raw:
        return raw
    for path in (raw, os.path.expanduser("~/.appstoreconnect/private_keys/"
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
        with urllib.request.urlopen(r, timeout=90) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


def show(label, path):
    status, payload = req("GET", path)
    print(f"\n=== {label} [{status}] {path}")
    if isinstance(payload, str):
        print(payload[:600])
    else:
        print(json.dumps(payload, indent=1)[:2500])


def discover():
    for var in ("APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_KEY_IDENTIFIER",
                "APP_STORE_CONNECT_PRIVATE_KEY"):
        val = os.environ.get(var, "")
        print(f"{var}: {'SET len=' + str(len(val)) if val else 'MISSING'}", flush=True)
    show("app", f"/v1/apps/{APP_ID}")
    show("app infos", f"/v1/apps/{APP_ID}/appInfos")
    show("version", f"/v1/appStoreVersions/{VERSION_ID}")
    show("version build", f"/v1/appStoreVersions/{VERSION_ID}/build")
    show("screenshot sets", f"/v1/appStoreVersionLocalizations/{LOCALIZATION_ID}/appScreenshotSets")
    show("price schedule", f"/v1/apps/{APP_ID}/appPriceSchedule")
    show("availability", f"/v1/apps/{APP_ID}/appAvailabilityV2")
    show("review detail", f"/v1/appStoreVersions/{VERSION_ID}/appStoreReviewDetail")
    # probes: do these exist for this key/app?
    show("probe data usages", f"/v1/apps/{APP_ID}/appDataUsages")
    show("probe data usage categories", f"/v1/apps/{APP_ID}/appDataUsageCategories")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "discover"
    if mode == "discover":
        discover()
    else:
        raise SystemExit(f"unknown mode {mode}")


if __name__ == "__main__":
    main()
