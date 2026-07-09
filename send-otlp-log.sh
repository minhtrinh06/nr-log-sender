#!/usr/bin/env bash
# Portable: runs under bash locally and busybox sh in-cluster (curlimages/curl).
set -u

# POST a fixed OTLP/HTTP resourceLogs payload (otlp-log.json, verbatim) to an
# OpenTelemetry collector, refreshing only timeUnixNano on each send.
# In-cluster it targets the fleet-managed New Relic pipeline-control-gateway,
# whose logs/otlp pipeline forwards to https://otlp.nr-data.net — so no
# license key is needed here.
#
# Usage:
#   ./send-otlp-log.sh                                   # loops forever, one log / 5s
#   INTERVAL=2 ./send-otlp-log.sh                        # change the cadence
#   OTLP_ENDPOINT=http://localhost:4318/v1/logs ...      # different collector
# Stop with Ctrl-C.

OTLP_ENDPOINT="${OTLP_ENDPOINT:-http://pipeline-control-gateway.newrelic.svc.cluster.local:4318/v1/logs}"
INTERVAL="${INTERVAL:-5}"
PAYLOAD_TEMPLATE="${PAYLOAD_TEMPLATE:-$(dirname "$0")/otlp-log.json}"

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

  status=$(sed "s/$PLACEHOLDER/$NOW_NS/" "$PAYLOAD_TEMPLATE" \
    | curl -sS -o /dev/null -w '%{http_code}' -X POST "$OTLP_ENDPOINT" \
        -H "Content-Type: application/json" \
        --data-binary @-) || status="000"

  printf '%s  #%-4d ts=%s  http=%s\n' "$(date +%H:%M:%S)" "$i" "$NOW_NS" "$status"
  sleep "$INTERVAL"
done
