# Xero OAuth credentials + org mapping.
# Copy this file to  xero_creds.local.py  (which is gitignored) and fill it in.
# NEVER commit real client secrets or org GUIDs.

# From your app at developer.xero.com (My Apps -> your app -> Configuration).
XERO_CLIENT_ID     = "PASTE_YOUR_CLIENT_ID"
XERO_CLIENT_SECRET = "PASTE_YOUR_CLIENT_SECRET"
XERO_REDIRECT_URI  = "http://localhost:8080/callback"   # must match the app's redirect URI

# Map each connected Xero organisation (by its Xero tenantId GUID) to the Dentally
# analytics Tenant_ID, and its default Practice Site. Run xero_extract.py once to see
# each connected org's GUID printed, then add it here.
#
# One org can host several sites split by tracking category -- that mapping lives in
# the warehouse (tracking option -> site); default_site_id is the fallback when a
# line has no tracking (and the whole org for a single-site practice).
XERO_ORG_MAP = {
    # "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx": {"tenant_id": 11, "default_site_id": 1},
    # Xero's Demo Company is auto-mapped to Tenant_ID 99 if omitted.
}
