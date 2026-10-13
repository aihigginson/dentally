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
import urllib.error
import urllib.request

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



# ==> HTTP GOES THROUGH CURL, NOT URLLIB. <== On this machine Python cannot reach
# api.fabric.microsoft.com or api.powerbi.com at all -- urllib and the Azure CLI's own urllib3
# both time out with WinError 10060 while curl answers in 0.13s, which is an IPv6-first hang in
# the Python stack rather than a Fabric outage. It cost a build trigger that silently never
# landed: the script reported a timeout, and the pipeline had no new run.
_NL = chr(10)          # written this way so no backslash escape can be mangled in transit


def _curl(url, method="GET", tok=None, payload=None):
    cmd = ["curl", "-s", "--max-time", "120", "-X", method,
           "-H", "Authorization: Bearer %s" % tok, "-w", _NL + "%{http_code}"]
    if payload is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(payload)]
    else:
        cmd += ["-H", "Content-Length: 0"]
    cmd.append(url)
    r = subprocess.run(cmd, capture_output=True, text=True, shell=False)
    body, _, code = r.stdout.rpartition(_NL)
    try:
        return int(code.strip() or 0), (json.loads(body) if body.strip() else {})
    except ValueError:
        return int(code.strip() or 0), {"raw": body[:400]}


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
