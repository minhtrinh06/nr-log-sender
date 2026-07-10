#!/usr/bin/env bash
# Portable: runs under bash locally and busybox sh in-cluster (curlimages/curl).
set -u

# Each sweep: for every *.json in PAYLOAD_DIR, splice the file into
# otlp-log.json as the log body (replacing the "__BODY__" marker), refresh
# timeUnixNano, and POST to an OpenTelemetry collector. The directory is
# re-globbed every sweep, so new payload files are picked up without a restart.
# In-cluster it targets the fleet-managed New Relic pipeline-control-gateway,
# whose logs/otlp pipeline forwards to https://otlp.nr-data.net — so no
# license key is needed here.
#
# Usage:
#   ./send-otlp-log.sh                                   # loops forever, one sweep / 5s
#   INTERVAL=2 ./send-otlp-log.sh                        # change the cadence
#   OTLP_ENDPOINT=http://localhost:4318/v1/logs ...      # different collector
#   PAYLOAD_DIR=./payloads ...                           # different payload dir
# Stop with Ctrl-C.

OTLP_ENDPOINT="${OTLP_ENDPOINT:-http://pipeline-control-gateway.newrelic.svc.cluster.local:4318/v1/logs}"
INTERVAL="${INTERVAL:-5}"
PAYLOAD_TEMPLATE="${PAYLOAD_TEMPLATE:-$(dirname "$0")/otlp-log.json}"
PAYLOAD_DIR="${PAYLOAD_DIR:-$(dirname "$0")/payloads}"

# The template's own example timestamp doubles as the substitution marker.
PLACEHOLDER="1783492434407676000"

trap 'echo; echo "stopped."; exit 0' INT

i=0
while true; do
  i=$((i + 1))
  # Current time in ns. busybox date lacks %N (emits it as empty or literal),
  # so unless we got 19+ pure digits, pad seconds to nanosecond precision.
  NOW_NS=$(date +%s%N)
  case "$NOW_NS" in
    *[!0-9]*) NOW_NS="" ;;
  esac
  [ "${#NOW_NS}" -ge 19 ] || NOW_NS="$(date +%s)000000000"

  sent=0
  for payload in "$PAYLOAD_DIR"/*.json; do
    [ -f "$payload" ] || continue
    sent=$((sent + 1))
    status=$(awk -v ts="$NOW_NS" -v ph="$PLACEHOLDER" -v pf="$payload" '{
        gsub(ph, ts)
        m = index($0, "\"__BODY__\"")
        if (m) {
          printf "%s", substr($0, 1, m - 1)
          while ((getline line < pf) > 0) print line
          printf "%s\n", substr($0, m + 10)
        } else print
      }' "$PAYLOAD_TEMPLATE" \
      | curl -sS -o /dev/null -w '%{http_code}' -X POST "$OTLP_ENDPOINT" \
          -H "Content-Type: application/json" \
          --data-binary @-) || status="000"

    printf '%s  #%-4d %-32s ts=%s  http=%s\n' \
      "$(date +%H:%M:%S)" "$i" "${payload##*/}" "$NOW_NS" "$status"
  done
  [ "$sent" -gt 0 ] || echo "no payloads in $PAYLOAD_DIR (waiting)"

  sleep "$INTERVAL"
done
