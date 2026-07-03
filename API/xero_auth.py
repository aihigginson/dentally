"""
xero_auth.py  --  One-time Xero OAuth2 consent handshake (authorization-code flow).

Run this once to authorise the app against a Xero organisation (e.g. the Demo
Company). It opens your browser, you consent + pick the org, and it saves the
tokens (access + refresh) and the connected tenant id(s) to
API/xero_token.local.json (gitignored). The extractor then uses/refreshes those.

Usage:
    python API/xero_auth.py

Requires: requests  (pip install requests)
Reads Client ID / secret / redirect URI from API/xero_creds.local.py.
"""
import base64
import importlib.util
import json
import os
import sys
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer

import requests

# The creds file has a dotted name (xero_creds.local.py) so it can't be a normal
# import — load it from its path.
_creds_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xero_creds.local.py")
if not os.path.exists(_creds_path):
    sys.exit("Missing API/xero_creds.local.py (copy the template and add your secret).")
_spec = importlib.util.spec_from_file_location("xero_creds_local", _creds_path)
creds = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(creds)

TOKEN_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xero_token.local.json")

AUTHORIZE_URL   = "https://login.xero.com/identity/connect/authorize"
TOKEN_URL       = "https://identity.xero.com/connect/token"
CONNECTIONS_URL = "https://api.xero.com/connections"

# Profitability slice — Xero's GRANULAR document scopes. We deliberately do NOT use
# accounting.journals.read (the general-ledger endpoint): it DOES exist, but is gated
# behind certification / a premium tier and is not grantable on connections created
# from 29 Apr 2026 — i.e. a new client next week couldn't consent to it. The document
# endpoints below reconcile to the P&L and any connection can grant them.
#   settings.read                = chart of accounts (Accounts) + tracking categories
#   invoices.read                = ACCREC (revenue) + ACCPAY (bills/costs) + credit notes
#   banktransactions.read        = cash spend/receive
#   manualjournals.read          = manual journals
#   payments.read                = payments
#   reports.profitandloss.read   = P&L report (reconciliation)
#   offline_access               = refresh token
SCOPES = (
    "openid profile email "
    "accounting.settings.read "
    "accounting.invoices.read "
    "accounting.banktransactions.read "
    "accounting.manualjournals.read "
    "accounting.payments.read "
    "accounting.reports.profitandloss.read "
    "offline_access"
)

_result = {}


class _CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != urllib.parse.urlparse(creds.XERO_REDIRECT_URI).path:
            self.send_response(404); self.end_headers(); return
        params = urllib.parse.parse_qs(parsed.query)
        _result["code"]  = params.get("code",  [None])[0]
        _result["error"] = params.get("error", [None])[0]
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        msg = "Xero authorisation complete - you can close this tab and return to the terminal."
        if _result.get("error"):
            msg = "Authorisation failed: " + _result["error"]
        self.wfile.write(("<html><body style='font-family:sans-serif;padding:40px'>"
                          + msg + "</body></html>").encode())

    def log_message(self, *args):
        pass  # silence the default logging


def _basic_auth_header():
    raw = f"{creds.XERO_CLIENT_ID}:{creds.XERO_CLIENT_SECRET}".encode()
    return "Basic " + base64.b64encode(raw).decode()


def main():
    if "PASTE_YOUR_CLIENT_SECRET" in creds.XERO_CLIENT_SECRET:
        sys.exit("Set XERO_CLIENT_SECRET in API/xero_creds.local.py first.")

    redirect = urllib.parse.urlparse(creds.XERO_REDIRECT_URI)
    host = redirect.hostname or "localhost"
    port = redirect.port or 80

    # 1. Build the authorize URL and open the browser.
    # quote_via=quote encodes spaces as %20 (not +). Xero's authorize endpoint
    # rejects '+' between scopes as one invalid scope string (invalid_scope).
    auth_url = AUTHORIZE_URL + "?" + urllib.parse.urlencode({
        "response_type": "code",
        "client_id":     creds.XERO_CLIENT_ID,
        "redirect_uri":  creds.XERO_REDIRECT_URI,
        "scope":         SCOPES,
        "state":         "analytically-slice",
    }, quote_via=urllib.parse.quote)
    print("Opening browser for Xero consent... (authorise, then pick the Demo Company)")
    print("If it doesn't open, paste this URL:\n" + auth_url + "\n")
    webbrowser.open(auth_url)

    # 2. Catch the redirect with the auth code.
    server = HTTPServer((host, port), _CallbackHandler)
    while "code" not in _result and "error" not in _result:
        server.handle_request()
    if _result.get("error"):
        sys.exit("Authorisation error: " + _result["error"])

    # 3. Exchange the code for tokens.
    resp = requests.post(TOKEN_URL, headers={
        "Authorization": _basic_auth_header(),
        "Content-Type":  "application/x-www-form-urlencoded",
    }, data={
        "grant_type":   "authorization_code",
        "code":         _result["code"],
        "redirect_uri": creds.XERO_REDIRECT_URI,
    })
    resp.raise_for_status()
    tokens = resp.json()

    # 4. Discover the connected tenant(s).
    conns = requests.get(CONNECTIONS_URL, headers={
        "Authorization": "Bearer " + tokens["access_token"],
        "Content-Type":  "application/json",
    })
    conns.raise_for_status()
    tenants = [{"tenantId": c["tenantId"], "tenantName": c.get("tenantName")}
               for c in conns.json()]

    with open(TOKEN_FILE, "w") as f:
        json.dump({"tokens": tokens, "tenants": tenants}, f, indent=2)

    print("\nSaved tokens + tenants to", TOKEN_FILE)
    print("Connected organisations:")
    for t in tenants:
        print(f"  - {t['tenantName']}  ({t['tenantId']})")
    print("\nNext: run the extractor to pull Journals / Accounts / Tracking.")


if __name__ == "__main__":
    main()
