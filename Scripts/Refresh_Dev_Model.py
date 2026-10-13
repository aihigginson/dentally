"""Refresh the DEV semantic model -- or PROD with an explicit --prod -- and poll it.

A build loads the warehouse; the model is a separate import and shows the PREVIOUS build's data
until this runs. A newly seeded tenant is invisible in the app -- its practices and sites are not
even in the pickers -- until the model has been refreshed.

DEV BY DEFAULT; prod needs an explicit --prod and will not be reached any other way. This costs
capacity on the shared F4 that also serves the live customer, so do not run it alongside a build
or a reseed -- and on prod, refresh only AFTER checking the warehouse figures are right. A refresh
is how wrong numbers reach the practice's screen.

    python Scripts/Refresh_Dev_Model.py             # Full refresh of DEV, polled
    python Scripts/Refresh_Dev_Model.py --prod      # ...of PROD, deliberately
    python Scripts/Refresh_Dev_Model.py --status    # report the latest refresh only
"""
import json
import subprocess
import sys
import time

# ==> PROD IS REACHABLE ONLY VIA AN EXPLICIT --prod. <== It is not the default and it never
# reads an environment variable, because the one failure mode that matters here is refreshing the
# live customer's model while believing you are on dev. Typing it is the point.
TARGET = {
    "dev":  ("22e235e2-7a32-4451-b573-8d5eb8532a23", "8d592796-f92f-4cb6-8fd6-dbe4c56d74b2"),
    "prod": ("2490d322-e8cc-4e9e-a3dc-964ce6fe444f", "f169053d-a538-4ee9-8d12-51098e1b90c1"),
}
ENV = "prod" if "--prod" in sys.argv else "dev"
WORKSPACE, DATASET = TARGET[ENV]
BASE = "https://api.powerbi.com/v1.0/myorg/groups/%s/datasets/%s" % (WORKSPACE, DATASET)



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
         "https://analysis.windows.net/powerbi/api", "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True, shell=True, check=True).stdout.strip()


def call(url, method="GET", tok=None, payload=None):
    # urllib cannot reach this host here; _curl can. Same contract, same returns.
    return _curl(url, method=method, tok=tok, payload=payload)


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
    print("refresh requested on %s (HTTP %s)" % (ENV.upper(), st))

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
