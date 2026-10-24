#!/usr/bin/env bash
# Layer 7 — a friendly name for the cluster on this host.
# Upserts "<master-ip>  inference.local" into /etc/hosts so the API and
# dashboards are reachable by name. Needs sudo once per cluster rebuild
# (the VM IP changes). Best-effort: if it fails, the raw IP keeps working.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

INFERENCE_HOST="${INFERENCE_HOST:-inference.local}"
MASTER_IP="$(vm_ip "${MASTER_NAME}")"
HOST_RE="${INFERENCE_HOST//./\\.}"

if grep -qE "^${MASTER_IP}[[:space:]]+${HOST_RE}\$" /etc/hosts; then
  log "/etc/hosts already maps ${INFERENCE_HOST} -> ${MASTER_IP}"
  exit 0
fi

log "Mapping ${INFERENCE_HOST} -> ${MASTER_IP} in /etc/hosts (may prompt for your password)"
CMD="sed -i '' '/[[:space:]]${HOST_RE}\$/d' /etc/hosts && printf '%s  %s\n' '${MASTER_IP}' '${INFERENCE_HOST}' >> /etc/hosts"
update_hosts() {
  if [[ -t 0 || -t 1 ]]; then
    sudo sh -c "${CMD}"
  else
    # No terminal for a sudo prompt — use the macOS admin-password dialog
    ESC="${CMD//\\/\\\\}"; ESC="${ESC//\"/\\\"}"
    osascript -e "do shell script \"${ESC}\" with administrator privileges" >/dev/null
  fi
}
if update_hosts; then
  log "${INFERENCE_HOST} now points at ${MASTER_IP}"
else
  warn "could not update /etc/hosts — use http://${MASTER_IP} wherever docs say ${INFERENCE_HOST}"
fi
