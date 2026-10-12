"""Refresh the DEV semantic model and poll to completion.

A build loads the warehouse; the model is a separate import and shows the PREVIOUS build's data
until this runs. A newly seeded tenant is invisible in the app -- its practices and sites are not
even in the pickers -- until the model has been refreshed.

DEV ONLY. The prod dataset is deliberately not named here. This costs capacity on the shared F4
that also serves the live customer, so do not run it alongside a build or a reseed.

    python Scripts/Refresh_Dev_Model.py             # Full refresh, polled
    python Scripts/Refresh_Dev_Model.py --status    # report the latest refresh only
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

WORKSPACE = "22e235e2-7a32-4451-b573-8d5eb8532a23"
DATASET = "8d592796-f92f-4cb6-8fd6-dbe4c56d74b2"
BASE = "https://api.powerbi.com/v1.0/myorg/groups/%s/datasets/%s" % (WORKSPACE, DATASET)


def token():
    return subprocess.run(
        ["az", "account", "get-access-token", "--resource",
         "https://analysis.windows.net/powerbi/api", "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True, shell=True, check=True).stdout.strip()


def call(url, method="GET", tok=None, payload=None):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, method=method, data=data)
    req.add_header("Authorization", "Bearer %s" % tok)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read().decode("utf-8")
            return r.status, (json.loads(body) if body.strip() else {})
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode("utf-8", "replace")[:400]}


def latest(tok):
    st, body = call(BASE + "/refreshes?$top=1", tok=tok)
    if st != 200:
        return None
    v = body.get("value") or []
    return v[0] if v else None


def main():
    tok = token()
    if "--status" in sys.argv:
        r = latest(tok)
        print(json.dumps(r, indent=2) if r else "no refreshes found")
        return 0

    st, body = call(BASE + "/refreshes", method="POST", tok=tok, payload={"type": "Full"})
    if st not in (200, 202):
        print("refresh FAILED %s: %s" % (st, body))
        return 1
    print("refresh requested (HTTP %s)" % st)

    last = None
    for _ in range(60):
        time.sleep(60)
        tok = token()
        r = latest(tok)
        if not r:
            continue
        status = r.get("status")
        if status != last:
            print("   %-12s start=%s" % (status, r.get("startTime")))
            last = status
        if status in ("Completed", "Failed", "Disabled"):
            if status != "Completed":
                print(json.dumps(r, indent=2)[:1500])
            return 0 if status == "Completed" else 1
    print("still refreshing after 60 minutes -- check with --status")
    return 1


if __name__ == "__main__":
    sys.exit(main())
