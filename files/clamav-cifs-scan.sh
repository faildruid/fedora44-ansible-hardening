#!/usr/bin/env bash
set -uo pipefail

readonly CONFIG=/etc/clamav/cifs-shares.conf
declare -a shares=()

log() { printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"; }

if [[ ! -r "$CONFIG" ]]; then
    log "ERROR: Cannot read $CONFIG"
    exit 2
fi

while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -z "$path" || "$path" =~ ^[[:space:]]*# ]] && continue
    if [[ "$path" != /* || "$path" == / || "$path" == *$'\r'* ]]; then
        log "ERROR: Invalid configured path: $path"
        exit 2
    fi
    shares+=("$path")
done < "$CONFIG"

if (( ${#shares[@]} == 0 )); then
    log "ERROR: No shares configured"
    exit 2
fi

if ! command -v clamscan >/dev/null 2>&1; then
    log "ERROR: clamscan not found"
    exit 2
fi

# Pre-flight: never scan the underlying local directories of missing mounts.
for path in "${shares[@]}"; do
    if ! findmnt -rn --mountpoint "$path" --types cifs >/dev/null; then
        log "ERROR: Not a mounted CIFS filesystem: $path"
        exit 2
    fi
    if [[ ! -d "$path" || ! -r "$path" || ! -x "$path" ]]; then
        log "ERROR: Mount path inaccessible: $path"
        exit 2
    fi
done

log "START: scanning ${#shares[@]} CIFS shares"
result=0
for path in "${shares[@]}"; do
    # Recheck before each share; the network connection may change.
    if ! findmnt -rn --mountpoint "$path" --types cifs >/dev/null; then
        log "ERROR: CIFS mount disappeared: $path"
        result=2
        continue
    fi

    log "SCAN: $path"
    clamscan --recursive --infected --stdout -- "$path"
    status=$?

    case "$status" in
        0) log "CLEAN: $path" ;;
        1)
            log "DETECTION: $path"
            (( result == 0 )) && result=1
            ;;
        *)
            log "ERROR: clamscan failed on $path (exit $status)"
            result=2
            ;;
    esac
done

log "FINISH: exit=$result (0=clean, 1=detection, 2=error)"
exit "$result"
