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

WORKSPACE = "22e235e2-7a32-4451-b573-8d5eb8532a23"
PIPELINE = "19eb0118-6767-4640-96fd-77b460ccb69a"
BASE = "https://api.fabric.microsoft.com/v1/workspaces/%s/items/%s" % (WORKSPACE, PIPELINE)



# ==> HTTP GOES THROUGH CURL, AND RETRIES. <== Python's urllib and the Azure CLI's own urllib3
# both fail here with WinError 10060 where curl succeeds. The first guess was an IPv6-first hang
# in the Python stack; that was WRONG -- forcing IPv4 fails too, and plain www.microsoft.com
# behaves identically. It is cold-connection resolution on this machine: the first contact with
# ANY host times out and the next is instant. A single-shot request always pays it, which is how
# a POST meant to start a build never reached Fabric while the script reported a timeout and the
# pipeline showed no new run. curl plus the retry below survives it; urllib alone did not.
_NL = chr(10)          # written this way so no backslash escape can be mangled in transit


def _curl(url, method="GET", tok=None, payload=None, tries=3):
    # ==> THE FIRST CONNECTION TO ANY HOST TIMES OUT; THE SECOND IS INSTANT. <== Measured:
    # api.fabric 12s timeout then 401 in 0.11s, api.powerbi 12s then 403 in 0.08s, and plain
    # www.microsoft.com the same. Cold-connection resolution on this machine, not a Fabric or
    # Power BI problem. A single-shot request always pays it, which is why the POST that was
    # meant to start a build never reached Fabric at all and the script called it a timeout.
    cmd = ["curl", "-s", "--max-time", "60", "-X", method,
           "-H", "Authorization: Bearer %s" % tok, "-w", _NL + "%{http_code}"]
    if payload is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(payload)]
    else:
        cmd += ["-H", "Content-Length: 0"]
    cmd.append(url)
    for attempt in range(tries):
        r = subprocess.run(cmd, capture_output=True, text=True, shell=False)
        body, _, code = r.stdout.rpartition(_NL)
        st = int(code.strip() or 0)
        if st:                       # 0 means curl never got a response at all
            try:
                return st, (json.loads(body) if body.strip() else {})
            except ValueError:
                return st, {"raw": body[:400]}
        if attempt + 1 < tries:
            print("   (no response from %s, retrying)" % url.split("/")[2])
            time.sleep(2)
    return 0, {"error": "no response after %d attempts" % tries}


def token():
    return subprocess.run(
        ["az", "account", "get-access-token", "--resource",
         "https://api.fabric.microsoft.com", "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True, shell=True, check=True).stdout.strip()


def call(url, method="GET", tok=None):
    # Third element was the response headers, which this no longer reads: the trigger's instance
    # id came from the Location header and is now simply not printed. latest() polls by start
    # time, so nothing depends on it.
    st, data = _curl(url, method=method, tok=tok)
    return st, data, {}


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
