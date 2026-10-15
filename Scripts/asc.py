#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""App Store Connect chores for Artemis's TestFlight builds, via the App Store Connect API.

  ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8=… \
    uv run -q --with pyjwt --with cryptography Scripts/asc.py <step> [args]

Steps (each is safe to run again):
  register           registers the bundle ID (the app record itself is made on the website)
  status             the app record, its bundle ID and the newest builds
  profile            the "Artemis App Store" profile for the Apple Distribution certificate,
                     made if missing and installed where Xcode looks for profiles
  group NAME EMAIL   internal TestFlight group NAME (all builds) with EMAIL as a tester
  wait BUILD         polls until build BUILD has finished processing; fails if it's invalid

The key needs App Manager (or Admin). It's never printed.
"""
import base64, json, os, pathlib, sys, time, urllib.error, urllib.request
import jwt

BUNDLE = "com.danielzn.artemis"
PROFILE = "Artemis App Store"
PROFILES_DIR = pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"

_token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                     "aud": "appstoreconnect-v1"}, os.environ["ASC_KEY_P8"], algorithm="ES256",
                    headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + _token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "body": e.read().decode()[:4000]}


def must(label, r):
    if "error" in r:
        sys.exit(f"{label}: FAILED {r['error']}: {r['body'][:600]}")
    return r


def app():
    apps = must("app", call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}"))["data"]
    if not apps:
        sys.exit(f"No App Store Connect app for {BUNDLE}: create it on the website (Apps → + → New App).")
    return apps[0]


def bundle_id():
    ids = must("bundle ID", call("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}"))["data"]
    match = [b for b in ids if b["attributes"]["identifier"] == BUNDLE]
    if not match:
        sys.exit(f"Bundle ID {BUNDLE} isn't registered (Certificates, Identifiers & Profiles → Identifiers).")
    return match[0]


def register():
    ids = must("bundle ID", call("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}"))["data"]
    if any(b["attributes"]["identifier"] == BUNDLE for b in ids):
        print(f"{BUNDLE} is already registered")
        return
    b = must("register", call("POST", "/v1/bundleIds", {"data": {
        "type": "bundleIds",
        "attributes": {"identifier": BUNDLE, "name": "Artemis", "platform": "IOS"}}}))["data"]
    print(f"registered {BUNDLE} ({b['id']})")


def status():
    a = app()
    print(f"app: {a['attributes']['name']} ({a['id']}), bundle {a['attributes']['bundleId']}, "
          f"SKU {a['attributes'].get('sku')}")
    b = bundle_id()
    caps = must("capabilities", call("GET", f"/v1/bundleIds/{b['id']}/bundleIdCapabilities"))["data"]
    print(f"bundle ID {b['id']}: capabilities {[c['attributes']['capabilityType'] for c in caps] or 'none'}")
    builds = must("builds", call("GET", f"/v1/builds?filter[app]={a['id']}&sort=-uploadedDate&limit=5"))["data"]
    for x in builds:
        print(f"build {x['attributes']['version']}: {x['attributes']['processingState']}, "
              f"uploaded {x['attributes']['uploadedDate']}")
    if not builds:
        print("no builds yet")


def profile():
    b = bundle_id()
    certs = must("certificates", call("GET", "/v1/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION"
                                            "&limit=50"))["data"]
    if not certs:
        sys.exit("No Apple Distribution certificate on the team.")
    # The newest certificate; it has to match the identity in this Mac's login keychain.
    cert = max(certs, key=lambda c: c["attributes"]["expirationDate"])
    found = must("profiles", call("GET", f"/v1/profiles?filter[name]={urllib.request.quote(PROFILE)}"
                                         "&filter[profileState]=ACTIVE&include=certificates"))
    prof = next((p for p in found["data"] if p["attributes"]["name"] == PROFILE), None)
    if prof and cert["id"] not in [c["id"] for c in prof["relationships"]["certificates"]["data"]]:
        must("delete stale profile", call("DELETE", f"/v1/profiles/{prof['id']}"))
        prof = None
    if prof is None:
        prof = must("create profile", call("POST", "/v1/profiles", {"data": {
            "type": "profiles",
            "attributes": {"name": PROFILE, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": b["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
            }}}))["data"]
        print(f"made profile {PROFILE} ({prof['id']})")
    attrs = prof["attributes"]
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    path = PROFILES_DIR / f"{attrs['uuid']}.mobileprovision"
    path.write_bytes(base64.b64decode(attrs["profileContent"]))
    print(f"installed {PROFILE}: uuid {attrs['uuid']}, expires {attrs['expirationDate']}, "
          f"certificate {cert['attributes']['name']} (expires {cert['attributes']['expirationDate']})")


def group(name, email):
    a = app()
    groups = must("groups", call("GET", f"/v1/apps/{a['id']}/betaGroups"))["data"]
    g = next((x for x in groups if x["attributes"]["name"] == name), None)
    if g is None:
        g = must("create group", call("POST", "/v1/betaGroups", {"data": {
            "type": "betaGroups",
            "attributes": {"name": name, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": a["id"]}}}}}))["data"]
        print(f"made group {name} ({g['id']})")
    print(f"group {name} ({g['id']}): internal={g['attributes']['isInternalGroup']}, "
          f"all builds={g['attributes']['hasAccessToAllBuilds']}")
    testers = must("testers", call("GET", f"/v1/betaGroups/{g['id']}/betaTesters"))["data"]
    t = next((x for x in testers if x["attributes"].get("email", "").lower() == email.lower()), None)
    if t is None:
        # Internal testers must be App Store Connect users; the tester joins this group.
        r = must("add tester", call("POST", "/v1/betaTesters", {"data": {
            "type": "betaTesters",
            "attributes": {"email": email},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": g["id"]}]}}}}))
        t = r["data"]
        print(f"added tester {email}")
    print(f"tester {email}: state {t['attributes'].get('state')}, invite type {t['attributes'].get('inviteType')}")


def wait(number):
    a = app()
    deadline = time.time() + 2 * 3600
    while time.time() < deadline:
        builds = must("builds", call("GET", f"/v1/builds?filter[app]={a['id']}&filter[version]={number}"))["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "NOT_YET_VISIBLE"
        print(f"{time.strftime('%H:%M:%S')} build {number}: {state}", flush=True)
        if state == "VALID":
            b = builds[0]
            beta = must("beta detail", call("GET", f"/v1/builds/{b['id']}/buildBetaDetail"))["data"]["attributes"]
            print(f"internal testing: {beta.get('internalBuildState')}")
            return
        if state in ("INVALID", "FAILED"):
            sys.exit(f"build {number} is {state}")
        time.sleep(60)
    sys.exit(f"build {number} still not processed after 2 hours")


if __name__ == "__main__":
    step = sys.argv[1] if len(sys.argv) > 1 else "status"
    if step == "register":
        register()
    elif step == "status":
        status()
    elif step == "profile":
        profile()
    elif step == "group" and len(sys.argv) > 3:
        group(sys.argv[2], sys.argv[3])
    elif step == "wait" and len(sys.argv) > 2:
        wait(sys.argv[2])
    else:
        sys.exit(__doc__)
