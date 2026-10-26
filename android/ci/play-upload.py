#!/usr/bin/env python3
"""Uploads one Taken bundle to a Google Play track (android/SPEC-ANDROID.md 15.4), from AAB #2 on.

    python3 -I ci/play-upload.py PACKAGE BUNDLE.aab TRACK STATUS

The Android Publisher API's edits flow, Google's documented order (https://developers.google.com/android-publisher/edits):
insert an edit, upload the bundle into it (edits.bundles.upload,
https://developers.google.com/android-publisher/api-ref/rest/v3/edits.bundles/upload), give the track a release with its
version code and status (edits.tracks.update, https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks),
then commit. Nothing changes on Play unless the commit succeeds: "If you try to commit an invalid edit, the operation
will throw an exception and have no effect" (edits page). Only Python's standard library, so no third-party publishing
tool sees the token [Own choice, SPEC-ANDROID 15.4].

The OAuth access token (scope androidpublisher) comes in PLAY_ACCESS_TOKEN from google-github-actions/auth's Workload
Identity Federation, and is never printed. The first bundle of an app must go through Play Console by hand, and the API
needs "an existing app (that has at least one APK uploaded)" (edits page), so this runs only from AAB #2.
"""
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
UPLOAD = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"
STATUSES = {"completed", "draft"}


def call(method, url, token, body=None, content_type="application/json"):
    data = json.dumps(body).encode() if isinstance(body, dict) else body
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        request.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(request, timeout=900) as response:
            text = response.read().decode() or "{}"
            return json.loads(text)
    except urllib.error.HTTPError as error:
        # Google's error body names the problem (a used version code, a draft app); it holds no credential.
        print(f"FAIL {method} {url.split('?')[0]}: HTTP {error.code}\n{error.read().decode(errors='replace')}")
        sys.exit(1)


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    package, bundle_path, track, status = sys.argv[1:]
    if status not in STATUSES:
        sys.exit(f"status must be one of {sorted(STATUSES)}, not {status!r}")
    token = os.environ.get("PLAY_ACCESS_TOKEN", "")
    if not token:
        sys.exit("PLAY_ACCESS_TOKEN is not set")

    edit = call("POST", f"{API}/{package}/edits", token, {})["id"]
    with open(bundle_path, "rb") as bundle:
        uploaded = call(
            "POST", f"{UPLOAD}/{package}/edits/{edit}/bundles?uploadType=media", token, bundle.read(), "application/octet-stream"
        )
    code = str(uploaded["versionCode"])
    print(f"OK   uploaded versionCode {code}, SHA-256 {uploaded.get('sha256', '?')}")
    call("PUT", f"{API}/{package}/edits/{edit}/tracks/{track}", token,
         {"track": track, "releases": [{"versionCodes": [code], "status": status}]})
    # The commit's request body must be empty; an explicit empty body still sends Content-Length: 0.
    call("POST", f"{API}/{package}/edits/{edit}:commit", token, b"")
    print(f"OK   versionCode {code} committed to the {track} track as {status}")


if __name__ == "__main__":
    main()
