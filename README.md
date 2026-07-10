# nr-log-sender

Sends test logs to New Relic as **OTLP/HTTP resourceLogs** payloads, for
exercising pipeline / parsing rules. Every `*.json` file in `payloads/` is a log
body; each sweep the sender splices each one into the `otlp-log.json` envelope
(replacing the `"__BODY__"` marker) and POSTs it, refreshing only
`timeUnixNano`. Envelope stays fixed: empty resource/scope/record attributes,
`severityText: DEBUG`.

It POSTs to the fleet-managed **pipeline-control-gateway** (an OTel collector,
`newrelic` namespace), whose `logs/otlp` pipeline forwards to
`https://otlp.nr-data.net` with the cluster's license key — so this workload
needs **no license key** of its own.

```
sender pod ──OTLP/HTTP──▶ pipeline-control-gateway:4318 ──▶ otlp.nr-data.net
```

## Files
- `payloads/*.json` — one file per log body (the JSON `body` value of the log
  record, e.g. `{"stringValue": "..."}`). One send per file per sweep.
- `otlp-log.json` — the resourceLogs envelope. `"__BODY__"` marks where the
  payload goes; the example timestamp (`1783492434407676000`) doubles as the
  substitution marker for `timeUnixNano`.
- `send-otlp-log.sh` — the sender. Loops forever, one sweep of all payloads
  every `INTERVAL` seconds. Runs under bash locally and busybox `sh` in-cluster.
- `deploy.sh` — applies everything: `apply -k` plus the payloads ConfigMap
  (built from `payloads/`, since kustomize can't glob a directory).
- `kustomization.yaml` — generates a ConfigMap from the script + envelope, plus
  the namespace + deployment.
- `k8s/namespace.yaml`, `k8s/deployment.yaml` — the workload (`curlimages/curl`).

## Run locally
The gateway's ClusterIP is reachable from the k3s host:
```sh
OTLP_ENDPOINT=http://$(sudo k3s kubectl -n newrelic get svc pipeline-control-gateway -o jsonpath='{.spec.clusterIP}'):4318/v1/logs ./send-otlp-log.sh
```

## Run in k3s (cluster: default)
`k3s kubectl` needs sudo (reads the root-only kubeconfig).

```sh
cd ~/Projects/nr-log-sender
./deploy.sh                                                       # apply -k + payloads configmap
sudo k3s kubectl -n nr-log-sender logs -f deploy/nr-log-sender    # watch http=200
```

## Add a payload
Drop a new `.json` file in `payloads/` and re-run `./deploy.sh`.
No manifest edits, no restart: the kubelet syncs the mounted
configmap in place (≤ ~1 min) and the script re-globs the directory every
sweep, so the new payload just starts flowing.

Change the cadence via `INTERVAL` in `k8s/deployment.yaml`; change the envelope
in `otlp-log.json`. For script/envelope changes re-run `./deploy.sh` — the
config hash change triggers a rolling restart automatically (then delete the
orphaned old ConfigMap).

## Verify in New Relic
```sql
SELECT * FROM Log WHERE newrelic.source = 'api.otlp' SINCE 10 minutes ago
```

## Tear down
```sh
sudo k3s kubectl delete -k .            # or: delete namespace nr-log-sender
```
