"""Additive T11 loader: keep every non-tenant-11 row in each stage_* Delta, swap in freshly
generated T11, write the union back. Bronze accumulates (no delete-not-in-source), so this only
ADDS T11 to the warehouse; the T100 guard asserts Tenant 100 counts never move. --dry-run = no write.
Auth via az-CLI storage token (avoids seed_onelake's interactive browser)."""
import sys, json, subprocess, argparse
import pandas as pd, pyarrow as pa
from datetime import datetime, timezone
from deltalake import DeltaTable, write_deltalake
import seed_onelake as S
from generate_data import generate_tenant

WS, LH = S.ENV_GUIDS["dev"]
def tok(): return subprocess.check_output(["az","account","get-access-token","--resource","https://storage.azure.com","--query","accessToken","-o","tsv"],shell=True).decode().strip()
def path(tn): return f"abfss://{WS}@onelake.dfs.fabric.microsoft.com/{LH}/Tables/dbo/stage_{tn}"
def _s(v):
    if v is None: return None
    if isinstance(v,bool): return '1' if v else '0'
    if isinstance(v,(dict,list)): return json.dumps(v)
    return str(v)

TABLE_MAP=[('practice','practice',True),('sites','sites',False),('users','users',False),('practitioners','practitioners',False),
('payment_plans','payment_plans',False),('treatments','treatments',False),('treatment_categories','treatment_categories',False),
('acquisition_sources','acquisition_sources',False),('cancellation_reasons','cancellation_reasons',False),('waiting_lists','waiting_lists',False),
('sundries','sundries',False),('contracts','contracts',False),('fees','fees',False),('diary_breaks','practitioner_diary_breaks',False),
('rooms','rooms',False),('patients','patients',False),('diary_entries','practitioner_diary_entries',False),('appointments','appointments',False),
('invoices','invoices',False),('invoice_items','invoice_items',False),('payments','payments',False),('treatment_plans','treatment_plans',False),
('treatment_plan_items','treatment_plan_items',False),('recalls','recalls',False),('nhs_claims','nhs_claims',False),('patient_stats','patient_stats',False),
('payment_allocations','payment_allocations',False),('payment_explanations','payment_explanations',False),('treatment_appts','treatment_appointments',False),
('patient_referrals','patient_referrals',False)]

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--dry-run",action="store_true"); a=ap.parse_args()
    load_ts=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S'); so={"bearer_token":tok()}
    print(f"Generating T11 ({S.T11['n_patients']:,} patients)..."); data=generate_tenant(S.T11)
    print(f"  patients={len(data['patients']):,} apts={len(data['appointments']):,} plans={len(data['treatment_plans']):,}")
    gen={}
    for dk,sn,wrap in TABLE_MAP:
        recs=[data[dk]] if wrap else data[dk]
        for r in recs: r['tenant_id']=str(11); r['DW_Stage_Loaded_At']=load_ts
        gen[sn]=[{k:_s(v) for k,v in r.items()} for r in recs]
    print(f"\n{'table':30} {'existing':>9} {'kept(non11)':>11} {'+T11':>7} {'T100 before/after':>18} {'guard'}")
    bad=0
    for _,sn,_w in TABLE_MAP:
        try: ex=DeltaTable(path(sn),storage_options=so).to_pandas()
        except Exception as e: print(f"  {sn:28} READ-ERR {str(e)[:40]}"); bad+=1; continue
        has_t=('tenant_id' in ex.columns)
        t100_before=int((ex['tenant_id']=='100').sum()) if has_t else 0
        kept= ex[ex['tenant_id']!='11'] if has_t else ex
        newdf=pd.DataFrame(gen[sn]).astype("string") if gen[sn] else pd.DataFrame()
        union=pd.concat([kept.astype("string"),newdf],ignore_index=True) if len(newdf) else kept
        t100_after=int((union['tenant_id']=='100').sum()) if 'tenant_id' in union.columns else 0
        ok = (t100_after==t100_before)
        if not ok: bad+=1
        print(f"  {sn:28} {len(ex):>9,} {len(kept):>11,} {len(newdf):>7,}   {t100_before:>7,}/{t100_after:<7,} {'OK' if ok else 'FAIL!!'}")
        if not a.dry_run and ok and len(union):
            write_deltalake(path(sn),pa.Table.from_pandas(union.astype("string"),preserve_index=False),mode="overwrite",schema_mode="overwrite",storage_options=so)
    print(f"\n{'DRY RUN — no writes.' if a.dry_run else 'WRITTEN.'}  T100 guard failures: {bad}")
    if bad: sys.exit(1)

if __name__=="__main__": main()
