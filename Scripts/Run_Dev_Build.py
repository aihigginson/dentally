"""Trigger the DEV warehouse build pipeline and poll it to completion.

Seeding only writes Bronze. Silver, Gold, the PBI views and anything derived (sites, dims,
aggregates) exist only after a build, so a newly seeded tenant is invisible to the app and the
model until this has run.

DEV ONLY -- the prod pipeline is deliberately not named here. Triggering a build costs capacity;
one F4 serves the live customer, so do not run this alongside a model refresh or a reseed.

    python Scripts/Run_Dev_Build.py            # trigger and poll
    python Scripts/Run_Dev_Build.py --status   # just report the latest run
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

WORKSPACE = "22e235e2-7a32-4451-b573-8d5eb8532a23"
PIPELINE = "19eb0118-6767-4640-96fd-77b460ccb69a"
BASE = "https://api.fabric.microsoft.com/v1/workspaces/%s/items/%s" % (WORKSPACE, PIPELINE)


def token():
    return subprocess.run(
        ["az", "account", "get-access-token", "--resource",
         "https://api.fabric.microsoft.com", "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True, shell=True, check=True).stdout.strip()


def call(url, method="GET", tok=None):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", "Bearer %s" % tok)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read().decode("utf-8")
            return r.status, (json.loads(body) if body.strip() else {}), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode("utf-8", "replace")[:400]}, dict(e.headers)


def latest(tok):
    st, body, _ = call(BASE + "/jobs/instances", tok=tok)
    if st != 200:
        return None
    runs = sorted(body.get("value") or [], key=lambda r: r.get("startTimeUtc") or "", reverse=True)
    return runs[0] if runs else None


def main():
    tok = token()
    if "--status" in sys.argv:
        r = latest(tok)
        print(json.dumps(r, indent=2) if r else "no runs found")
        return 0

    st, body, hdrs = call(BASE + "/jobs/instances?jobType=Pipeline", method="POST", tok=tok)
    if st not in (200, 202):
        print("trigger FAILED %s: %s" % (st, body))
        return 1
    # 202 returns the instance in the Location header, not the body.
    loc = hdrs.get("Location") or ""
    print("triggered (HTTP %s)%s" % (st, "  " + loc.rsplit("/", 1)[-1] if loc else ""))

    # Poll. A dev build runs 25-50 minutes; a 60s interval is plenty and costs nothing.
    last = None
    for _ in range(90):
        time.sleep(60)
        tok = token()               # the token outlives a build only just; refresh each poll
        r = latest(tok)
        if not r:
            continue
        status = r.get("status")
        if status != last:
            print("   %-12s start=%s" % (status, r.get("startTimeUtc")))
            last = status
        if status in ("Completed", "Failed", "Cancelled", "Deduped"):
            if status != "Completed":
                print(json.dumps(r.get("failureReason") or r, indent=2)[:1200])
            return 0 if status == "Completed" else 1
    print("still running after 90 minutes -- check with --status")
    return 1


if __name__ == "__main__":
    sys.exit(main())
