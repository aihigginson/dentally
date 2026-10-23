#!/usr/bin/env bash
# Stand up caj-capacity-schedule-prod. Run in Azure Cloud Shell.
#
# WHY CLOUD SHELL. Azure refuses create/update/delete from a token with no MFA claim
# (RequestDisallowedByAzure), and on this Windows workstation the az CLI signs in through
# the Windows broker, which satisfies the sign-in from the device's cached credential and
# returns amr ['pwd','rsa'] -- no second factor, however many times you log out and back
# in. Cloud Shell inherits the portal session, which the policy does force MFA on.
#
# WHY A FILE AND NOT A PASTE. Pasting from Windows into Cloud Shell carries CR characters
# that break every line. Upload this file with the Cloud Shell "Upload/Download files"
# button instead, then:
#
#     tr -d '\r' < create_capacity_job.sh > j.sh && bash j.sh
#
# The tr is belt and braces in case the file picks up CRs in transit; it is short enough
# to type by hand, which is the whole point.
#
# Safe to re-run: it reports what already exists rather than duplicating it.
set -euo pipefail

RG=rg-analytically
JOB=caj-capacity-schedule-prod
ENVIRONMENT=cae-analytically
IMAGE=analyticallyacr.azurecr.io/analytically:latest
REGISTRY=analyticallyacr.azurecr.io
SUB=b24ec454-d0b6-4a06-8063-ee59335558b8
SCOPE="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Fabric/capacities/analytically"

# Hourly at :45, with the script's own 15-minute lead, so each firing asks what should be
# true at the top of the next hour. Hourly rather than only at the four boundaries so a
# failed run is corrected within the hour instead of leaving the capacity wrong overnight.
CRON='45 * * * *'

echo "== 1. the job"
if az containerapp job show -n "$JOB" -g "$RG" --query name -o tsv 2>/dev/null; then
    echo "   already exists -- skipping create"
else
    az containerapp job create \
        -n "$JOB" -g "$RG" \
        --environment "$ENVIRONMENT" \
        --trigger-type Schedule --cron-expression "$CRON" \
        --replica-timeout 600 --replica-retry-limit 1 \
        --parallelism 1 --replica-completion-count 1 \
        --image "$IMAGE" \
        --cpu 0.5 --memory 1Gi \
        --mi-system-assigned \
        --registry-server "$REGISTRY" \
        --command python --args capacity_schedule.py \
        -o none
    echo "   created"
fi

echo "== 2. the one role assignment it needs"
# Contributor on the CAPACITY RESOURCE only -- not the resource group. The app's service
# principal is deliberately not reused: it holds no rights over Azure resources at all.
PRINCIPAL=$(az containerapp job show -n "$JOB" -g "$RG" --query identity.principalId -o tsv)
echo "   managed identity: $PRINCIPAL"
if az role assignment list --assignee "$PRINCIPAL" --scope "$SCOPE" \
        --query "[?roleDefinitionName=='Contributor'] | [0].id" -o tsv 2>/dev/null | grep -q .; then
    echo "   Contributor already granted"
else
    az role assignment create --assignee-object-id "$PRINCIPAL" \
        --assignee-principal-type ServicePrincipal \
        --role Contributor --scope "$SCOPE" -o none
    echo "   granted; waiting 30s for it to propagate"
    sleep 30
fi

echo "== 3. prove it end to end"
# A job execution is the only honest test: it exercises the image, the identity and the
# role assignment together. --dry-run reads the capacity and reports, changing nothing.
EXEC=$(az containerapp job start -n "$JOB" -g "$RG" \
    --command python --args capacity_schedule.py --args --dry-run \
    --query name -o tsv)
echo "   execution: $EXEC"
for _ in $(seq 1 30); do
    sleep 10
    STATUS=$(az containerapp job execution show -n "$JOB" -g "$RG" \
        --job-execution-name "$EXEC" --query properties.status -o tsv 2>/dev/null || true)
    case "$STATUS" in Running|Processing|"") ;; *) break ;; esac
done
echo "   status: $STATUS"
echo
az containerapp job logs show -n "$JOB" -g "$RG" --execution "$EXEC" --container "$JOB" --tail 30 || true
echo
echo "Expect a line like: Fri 18:45 UK -> target F4; capacity is F4, Active"
