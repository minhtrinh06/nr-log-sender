# nr-log-sender

Sends a fixed test log to New Relic as an **OTLP/HTTP resourceLogs** payload, for
exercising pipeline / parsing rules. The payload (`otlp-log.json`) is sent
verbatim — empty resource/scope/record attributes, `severityText: DEBUG`, and the
embedded `Body: {\"...\"}` JSON inside the body string — with only `timeUnixNano`
refreshed per send.

It POSTs to the fleet-managed **pipeline-control-gateway** (an OTel collector,
`newrelic` namespace), whose `logs/otlp` pipeline forwards to
`https://otlp.nr-data.net` with the cluster's license key — so this workload
needs **no license key** of its own.

```
sender pod ──OTLP/HTTP──▶ pipeline-control-gateway:4318 ──▶ otlp.nr-data.net
```

## Files
- `otlp-log.json` — the exact resourceLogs payload. Its example timestamp
  (`1783492434407676000`) doubles as the substitution marker for `timeUnixNano`.
- `send-otlp-log.sh` — the sender. Loops forever, one POST every `INTERVAL`
  seconds. Runs under bash locally and busybox `sh` in-cluster.
- `kustomization.yaml` — generates a ConfigMap from the script + payload, plus
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
sudo k3s kubectl apply -k .
sudo k3s kubectl -n nr-log-sender rollout status deploy/nr-log-sender
sudo k3s kubectl -n nr-log-sender logs -f deploy/nr-log-sender    # watch http=200
```

Change the cadence via `INTERVAL` in `k8s/deployment.yaml`; change the payload in
`otlp-log.json`. Re-run `apply -k .` — the config hash change triggers a rolling
restart automatically (then delete the orphaned old ConfigMap).

## Verify in New Relic
```sql
SELECT * FROM Log WHERE newrelic.source = 'api.otlp' SINCE 10 minutes ago
```

## Tear down
```sh
sudo k3s kubectl delete -k .            # or: delete namespace nr-log-sender
```
