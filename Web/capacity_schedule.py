"""Hold the 'analytically' Fabric capacity at the SKU the time of day calls for.

Runs as a Container Apps Job. It was a GitHub Actions cron until 23/10/2026, and that is
why it moved: measured over two weeks, NOT ONE of fourteen scheduled firings ran on time,
half never ran at all, and the median delay was four hours eight minutes. The 05:45 resume
was landing at about 09:36, so the site was down for the first four hours of the working
day and caj-appdb-sync-prod failed every ten minutes from 07:00 until someone resumed the
capacity by hand. Container Apps job executions, on the same subscription, fire to the
minute.

    python capacity_schedule.py                 apply the schedule for now
    python capacity_schedule.py --dry-run       say what it would do, change nothing
    python capacity_schedule.py --at 23:30      evaluate a particular UK time
    python capacity_schedule.py --table         print the whole day and exit

==> UK LOCAL IS TREATED AS UTC. <== Deliberate, and only correct from 25/10/2026, when the
clocks go back. This is a cost-control measure meant to be switched off before the clocks
go forward again in spring, so it carries no timezone database and no BST handling -- the
PowerShell it replaces fired at the union of both offsets' boundaries to cope, which is
complexity bought for a case that is not going to arrive. UNTIL the clocks change this
weekend the schedule runs an hour late in UK terms: the only visible effect is the capacity
resuming at 07:00 rather than 06:00 on Saturday and Sunday morning.

If this is still running when BST returns, the fix is a real one, not a fudge: take
UK_IS_UTC out, import zoneinfo, and convert. Do not shift the hours by one.
"""
import argparse
import os
import sys
import time
from datetime import datetime, timedelta, timezone

import requests

SUB = os.environ.get('AZURE_SUBSCRIPTION_ID', 'b24ec454-d0b6-4a06-8063-ee59335558b8')
RG = os.environ.get('CAPACITY_RG', 'rg-analytically')
NAME = os.environ.get('CAPACITY_NAME', 'analytically')
API = '2023-11-01'
BASE = (f'https://management.azure.com/subscriptions/{SUB}/resourceGroups/{RG}'
        f'/providers/Microsoft.Fabric/capacities/{NAME}')

UK_IS_UTC = True            # see the module docstring before changing this
LEAD_MINUTES = 15           # ask "what should be true in 15 minutes?", so it has LANDED
TIER = 'Fabric'

# "from this UK local hour, hold this SKU, until the next row." 'pause' is a legal value:
# it stops compute billing entirely, which is worth far more than F2 overnight.
SCHEDULE = [
    (0,  'pause'),   # nothing is scheduled 00:00-06:00; the hour histogram in
                     # Audit.Process_Execution_Log is empty across 14 days
    # ==> F4 FROM 06:00, NOT F2. <== The catch-all semantic model refresh runs at 07:00 and
    # is memory-hungry in exactly the way halving the SKU punishes.
    (6,  'F4'),      # working day
    (18, 'F2'),      # evening
    (22, 'F4'),      # the nightly build, 22:03 to about 22:37
]


def target_for(hour):
    pick = SCHEDULE[-1][1]          # before the first row, yesterday's last window holds
    for frm, sku in SCHEDULE:
        if hour >= frm:
            pick = sku
    return pick


def uk_now(at=None):
    if at:
        h, m = (int(x) for x in at.split(':'))
        base = datetime.now(timezone.utc).replace(hour=h, minute=m, second=0, microsecond=0)
    else:
        base = datetime.now(timezone.utc)
        if not UK_IS_UTC:
            raise RuntimeError('UK_IS_UTC is off but no conversion is implemented')
    return base + timedelta(minutes=LEAD_MINUTES)


def token():
    """One credential chain for three homes.

    ==> THE JOB AUTHENTICATES AS ITSELF, NOT AS THE APP. <== In Container Apps this resolves
    the job's system-assigned managed identity, which holds Contributor on the CAPACITY
    RESOURCE ONLY -- not the resource group, and not the app's service principal, which has
    no rights over Azure resources at all. On a workstation the same call falls through to
    the signed-in az CLI, so --dry-run works without a secret anywhere.
    """
    from azure.identity import DefaultAzureCredential
    return DefaultAzureCredential().get_token(
        'https://management.azure.com/.default').token


def call(method, url, tok, **kw):
    r = requests.request(method, url, timeout=60,
                         headers={'Authorization': f'Bearer {tok}',
                                  'Content-Type': 'application/json'}, **kw)
    if r.status_code >= 400:
        raise RuntimeError(f'{method} {url.split("/providers/")[-1]} -> '
                           f'{r.status_code} {r.text[:300]}')
    return r


def read(tok):
    body = call('GET', f'{BASE}?api-version={API}', tok).json()
    return body.get('properties', {}).get('state'), body.get('sku', {}).get('name')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--at', help='UK local HH:mm to evaluate instead of now')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--table', action='store_true', help='print the day and exit')
    a = ap.parse_args()

    if a.table:
        for h in range(24):
            print(f'  {h:02d}:00 UK -> {target_for(h)}')
        return 0

    now = uk_now(a.at)
    want = target_for(now.hour)
    tok = token()
    state, sku = read(tok)
    print(f'{now:%a %H:%M} UK -> target {want}; capacity is {sku}, {state}')

    if want == 'pause':
        if state in ('Paused', 'Suspended'):
            print('Already paused.')
            return 0
        if a.dry_run:
            print('DRY RUN: would suspend.')
            return 0
        call('POST', f'{BASE}/suspend?api-version={API}', tok)
        print('Paused -- compute billing stopped.')
        return 0

    # ==> A PAUSED CAPACITY CANNOT BE RESIZED, SO RESUME FIRST AND SCALE AFTER. <==
    if state in ('Paused', 'Suspended'):
        if a.dry_run:
            print(f'DRY RUN: would resume, then scale to {want} if needed.')
            return 0
        print('Capacity is paused and the schedule wants it running -- resuming ...')
        call('POST', f'{BASE}/resume?api-version={API}', tok)
        for _ in range(40):
            time.sleep(5)
            state, sku = read(tok)
            if state == 'Active':
                break
        else:
            print('Resume did not reach Active within 200s.', file=sys.stderr)
            return 1

    if sku == want:
        print(f'Already {want} -- nothing to do.')
        return 0
    if a.dry_run:
        print(f'DRY RUN: would scale {sku} -> {want}.')
        return 0

    print(f'Scaling {sku} -> {want} (reports are briefly unavailable during the change) ...')
    # The tier travels with the name or ARM rejects the patch.
    call('PATCH', f'{BASE}?api-version={API}', tok,
         json={'sku': {'name': want, 'tier': TIER}})
    _, after = read(tok)
    if after != want:
        print(f'Scale did not take: still {after}.', file=sys.stderr)
        return 1
    print(f'SKU now {after}.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
