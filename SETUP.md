# New-Machine Setup

Rebuild a working dev environment on a fresh Windows PC. Because this project is
cloud-first (code in GitHub, files in OneDrive, data + compute in Fabric/Azure),
setup is **install tools → sign in**. There is no "copy my files" step.

Estimated time: ~1–2 hours, mostly unattended installs + one OneDrive sync.

---

## 0. What lives where (nothing is machine-only)

| Asset | Source of truth | Comes back via |
|-------|-----------------|----------------|
| Tracked code (SQL, Python, PBIR, docs) | GitHub `origin` (`dev` default branch) | `git`/OneDrive |
| `.pbix` Power BI files (gitignored) | OneDrive | OneDrive sync |
| Local secret files (`*.local`, `.env`) | OneDrive (copies); real values below | OneDrive sync |
| Warehouse data + build | Fabric (`WH_Dentally`, dev + prod workspaces) | cloud, nothing local |
| Real secrets of record | Azure Key Vault / GitHub secrets / Container App secrets | see §5 |
| **Claude Code state** (memories, MCP, settings) | `<repo>/.claude/` — see §8 | OneDrive + git, via a junction |

**You cannot lose data by replacing the machine.** The only pre-move check is
that OneDrive says *"Your files are up to date"* on the old PC before you wipe it.

> **Except what lives outside OneDrive.** Anything in the Windows user profile — notably
> `~/.claude` — is **not** covered by any of the above. Learned the hard way on the 2026-09
> move, when every Claude memory was lost. See §8.

---

## 1. OneDrive first (this restores everything)

1. Install OneDrive, sign in with the work account.
2. Let it sync `…\OneDrive\dentally\` fully — this pulls the whole repo back,
   **including** the gitignored `.pbix` files and the `*.local` / `.env` secret
   files. Wait for "up to date" before assuming anything is missing.
3. The repo path will be `…\OneDrive\dentally\code`.

> If you'd rather have a clean git clone instead of the OneDrive copy, you can
> `git clone` from GitHub into a **non-OneDrive** path — but then you must
> re-create the gitignored secret files (§5). The OneDrive copy already has them,
> so syncing is simpler. Do **not** put a second clone *inside* OneDrive.

---

## 2. Core tools

Run in an elevated PowerShell (winget covers most):

```powershell
winget install --id Git.Git -e
winget install --id Python.Python.3.12 -e
winget install --id Microsoft.AzureCLI -e
winget install --id GitHub.cli -e
winget install --id Microsoft.PowerBI -e            # Power BI Desktop
winget install --id Microsoft.VisualStudioCode -e   # or SSMS if you prefer
```

Claude Code (native, no Node needed):

```powershell
irm https://claude.ai/install.ps1 | iex
```

If `claude` isn't found in a new shell, add it to PATH once:

```powershell
[Environment]::SetEnvironmentVariable("Path",
  [Environment]::GetEnvironmentVariable("Path","User") + ";$env:USERPROFILE\.local\bin",
  "User")
```

Then close **all** PowerShell windows and open a fresh one.

Optional: **SQL Server Management Studio (SSMS)** if you query the warehouse
directly — Windows Auth / AAD account (this account has MFA; use `-G -U <user>`
with **no** `-P`).

---

## 3. Sign in to everything

```powershell
az login                      # Azure CLI  (SP/user as normal)
gh auth login                 # GitHub CLI
claude                        # then /login with the existing subscription
```

- **Power BI Desktop** — sign in with the work account (top-right).
- **OneDrive** — already done in §1.

---

## 4. Python environments

Two independent Python apps. Create a venv for each:

```powershell
# Web app (Flask front-end + monitor)
cd $HOME\OneDrive\dentally\code\Web
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt -r requirements-dev.txt
python -m pytest        # sanity: 44 tests should pass
deactivate

# API (mock/ingest helpers)
cd ..\API
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
deactivate
```

`Scripts\_q.py` / `_qp.py` (local warehouse query helpers, untracked) need
`pyodbc` + the **ODBC Driver 18 for SQL Server**:

```powershell
winget install --id Microsoft.msodbcsql.18 -e
pip install pyodbc azure-identity      # into whichever venv you run them from
```

> Reminder: `_q.py`/`_qp.py` have **no autocommit** — DML rolls back. For
> `EXEC`/DML use a `pyodbc.connect(..., autocommit=True)` one-liner instead.

---

## 5. Secret files (only if NOT restored via OneDrive)

If you used the OneDrive copy (§1) these already exist and you can skip this.
If you did a fresh git clone outside OneDrive, re-create them. Real values live
in Azure Key Vault / GitHub secrets / Container App secrets — never commit them.

| File | Purpose | Where the real values live |
|------|---------|----------------------------|
| `Web\.env` | Flask app config (see key names below) | Container App secrets + Key Vault |
| `API\.env.txt` | mock/ingest API config | local dev only |
| `API\dentally_creds.local.py` | Dentally PAT for local ingest tests | KV `dentally-tokens-<env>` |
| `API\xero_creds.local.py` | Xero client id/secret | KV |
| `API\xero_token.local.json` | cached Xero OAuth token | regenerated by OAuth flow |
| `Scripts\fabric_creds.local.ps1` | Fabric SP creds for deploy scripts | see `.example`; KV |

`Scripts\fabric_creds.local.ps1.example` is tracked — copy it and fill in.

Key `Web\.env` variable names (values from Container App / KV, **not** here):
`APP_ENV`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `FABRIC_DB`, `APPDB_SERVER`,
`APPDB_DB`, `GRAPH_SEND`, `GRAPH_FROM`, `MONITOR_KEY`, `MONITOR_NOTIFY`,
`ONBOARDING_NOTIFY`, `REPORT_ID_*` (one per PBI report). For **local** runs set
`APP_ENV=dev` so no customer emails ever send.

To read a KV secret value when rebuilding (read-only, needs `az login`):

```powershell
az keyvault secret show --vault-name kv-analytically --name <secret-name> --query value -o tsv
```

---

## 6. Verify

```powershell
cd $HOME\OneDrive\dentally\code
git status            # clean, on dev, up to date with origin
git log --oneline -3  # matches GitHub
claude --version
az account show
```

- Open a `.pbix` in Power BI Desktop → it renders (report + model intact).
- `cd Web; .\.venv\Scripts\Activate.ps1; python -m pytest` → 44 pass.

Done — you're back to a full working environment.

---

## 7. Personal browser logins (HMRC, Microsoft, banking, etc.)

These are **website logins saved in a browser**, not project secrets. They ride
the browser's account sync to the new PC — nothing is machine-bound *as long as
sync is on*. The carrier depends on the browser:

- **Chrome → your Google account** (where these logins are saved here)
- **Edge → your Microsoft account** (separate sign-in from Chrome)

### Chrome (the important one for these logins)
The cloud store behind Chrome is **Google Password Manager** —
[passwords.google.com](https://passwords.google.com) is just its web view. If a
login shows there, it's in your Google account and syncs to any machine.

1. **Old PC, today** (time-sensitive — the SSD is dying):
   - `chrome://settings/syncSetup` → signed in to Chrome + **Sync (Passwords) On**.
   - Confirm your logins appear at **passwords.google.com** = they're safely in the cloud.
   - Backup anyway: `chrome://password-manager/passwords` → **Settings** → **Export
     passwords** → CSV. **Plain-text** — store safely (encrypted USB / protected
     file), **delete once the new PC is set up**.
2. **New PC:** install Chrome → sign in with the **same Google account** → Sync On
   → passwords repopulate.

### Finding a login that "isn't in the list"
Entries are filed by the site's **real login domain, not its brand name**. HMRC's
Government Gateway saves under **gov.uk** domains (e.g. `access.service.gov.uk`,
`tax.service.gov.uk`), so searching "HMRC" misses it — search **"gov.uk"** or
**"service.gov.uk"** instead.

### Caveats
- **Sync OFF = local only.** Passwords saved while Chrome sync was off live only
  in the local profile on this SSD, not the cloud. The CSV export is the **only**
  safety net for those — so do the export.
- **MFA (HMRC, Microsoft, banking):** expect a **one-time re-challenge** on the new
  device. Keep your **phone / authenticator app** — that's what clears it. Normal
  security, not a migration failure.
- **Windows Hello PIN / fingerprint** are device-bound by design — set up fresh on
  the new PC; the account behind them is unchanged.

---

## 8. Claude Code state (memories, MCP, settings)

Claude Code keeps its state in `%USERPROFILE%\.claude` — **outside OneDrive**, so unlike
everything in §0 it does *not* come back on its own.

**What survives without help**

- `.claude/settings.local.json` (permission rules) — lives in the repo, restored by OneDrive.
- `CLAUDE.md` — in the repo.
- `~/.claude.json` (MCP server definitions, project history) — machine-local and rebuilt on
  first run, but the servers still need re-authenticating (below).

**Memories — no other copy unless you make one.** They are kept in the repo at
`.claude/memory/` and exposed to Claude through a directory junction, so anything Claude
writes lands in a synced, version-controlled folder automatically:

```powershell
# find the slug (it is the repo's full path with ':' and '\' replaced by '-')
Get-ChildItem "$env:USERPROFILE\.claude\projects" -Directory

$slug   = 'C--users-aihig-onedrive-dentally-code'
$link   = "$env:USERPROFILE\.claude\projects\$slug\memory"
$target = 'C:\Users\aihig\OneDrive\Dentally\Code\.claude\memory'
if ((Test-Path $link) -and -not (Get-ChildItem $link -File)) { Remove-Item $link -Recurse -Force }
New-Item -ItemType Junction -Path $link -Target $target
```

No admin rights needed. **If the repo ever moves the slug changes** — recreate the junction,
or Claude starts up silently with no memories and nothing appears to be wrong.

**Session transcripts — the other thing with no copy.** Claude keeps every session verbatim
at `%USERPROFILE%\.claude\projects\<slug>\<session-uuid>.jsonl`, with oversized tool output
spilled into a sibling `<session-uuid>\tool-results\`. This is what `/resume` and
`--continue` read, and what Claude itself reads back to recover detail lost to compaction.
It is not synced and dies with the machine.

A junction will not work here — Claude appends to the live `.jsonl` continuously and OneDrive
would churn on every write — so copy on demand instead:

```powershell
.\Scripts\Backup-ClaudeTranscripts.ps1          # -> <OneDrive>\ClaudeTranscripts\<COMPUTERNAME>\
```

Re-run it at the end of a session to capture the tail; unchanged files are skipped. The
destination is deliberately **outside the repo** and the script refuses to write inside a git
working tree: a transcript is unredacted, so it holds warehouse connection strings, real
patient and practitioner names, and anything else that was pasted in. Never commit one.

Note the session UUID in the filename is *not* the `session_…` id that appears in
`Claude-Session:` commit trailers — they are separate identifiers and neither finds the other.

**MCP servers** — expect `! Needs authentication` on a new machine. Run `claude`, then `/mcp`,
and complete the browser login for each (Microsoft 365, Google Drive).

**PowerShell execution policy** — set this before installing any module (Microsoft Graph etc.):

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

A fresh Windows 11 profile defaults to `Restricted`, which refuses to load `.psm1` files and
reports it as a misleading *"the module could not be loaded"* error.

**Verify**

```powershell
(Get-Item "$env:USERPROFILE\.claude\projects\$slug\memory").LinkType   # -> Junction
claude mcp list                                                        # -> no "Needs authentication"
Get-ChildItem "$env:OneDrive\ClaudeTranscripts\$env:COMPUTERNAME" -Recurse -File |
    Measure-Object Length -Sum                                         # -> transcripts present
```

---

## Recommended spec (for reference)

Local compute is light because heavy work runs in Fabric. Prioritise **RAM**
(Power BI Desktop is the memory hog):

- **RAM: 32 GB** (16 GB works but you'll feel it) — the one thing worth not skimping on
- **NVMe SSD: 1 TB** (512 GB is tight once OneDrive + tools land)
- **CPU:** any current mid-range (Core Ultra 5/7, Ryzen 5/7)
- **GPU:** integrated is fine — nothing here needs discrete
- **OS:** Windows 11
