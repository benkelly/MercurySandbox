#!/usr/bin/env bash
# Kubernetes backend: each sandbox is a Job with the same hardening the
# Docker backend applies, in the namespace the controller runs in. Secrets go
# in a per-sandbox Secret owned by the Job, so they are deleted with it.
#
# Needs kubectl and a ServiceAccount allowed to manage jobs, pods, pods/log
# and secrets in that namespace (the Helm chart sets this up). Interactive
# modes (TUI, --shell) are Docker-only; use `mercury exec` on a running Job.
#
# Reads the SPEC_* globals that lib/sandbox.sh sets up.

backend_name() { printf 'kubernetes'; }

kube_ns() {
  if [ -n "${KUBE_NAMESPACE:-}" ]; then
    printf '%s' "$KUBE_NAMESPACE"
  elif [ -r /var/run/secrets/kubernetes.io/serviceaccount/namespace ]; then
    cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
  else
    printf 'default'
  fi
}

kc() { kubectl --namespace "$(kube_ns)" "$@"; }

backend_ok() { kc auth can-i create jobs >/dev/null 2>&1; }

# Docker-style sizes to Kubernetes quantities: 2g -> 2Gi, 512m -> 512Mi.
kube_quantity() {
  case "$1" in
    *[gG]) printf '%sGi' "${1%[gG]}" ;;
    *[mM]) printf '%sMi' "${1%[mM]}" ;;
    *[kK]) printf '%sKi' "${1%[kK]}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# KEY=VALUE lines on stdin -> JSON object
kv_to_object() {
  jq -Rn '[inputs | select(length > 0) | capture("^(?<k>[^=]+)=(?<v>.*)$") | {key: .k, value: .v}] | from_entries'
}

backend_spawn() {
  case "$SPEC_MODE" in
    shell | tui) die "the kubernetes backend runs tasks only; give a task, or use SANDBOX_BACKEND=docker for the TUI" ;;
  esac
  local ns mem cpu env_json secret_json deadline
  ns="$(kube_ns)"
  mem="$(kube_quantity "$SPEC_MEMORY")"
  cpu="$SPEC_CPUS"
  deadline=$(( ${SPEC_TIMEOUT:-3600} + 600 ))
  env_json="$(printf '%s\n' "${SPEC_ENV[@]}" | kv_to_object | jq '[to_entries[] | {name: .key, value: .value}]')"
  secret_json="$(printf '%s\n' "${SPEC_SECRET_ENV[@]}" | kv_to_object)"

  local job
  job="$(jq -n \
    --arg name "$SPEC_NAME" --arg ns "$ns" --arg image "$SPEC_IMAGE" \
    --arg repo "$SPEC_REPO" --arg branch "$SPEC_BRANCH" --arg model "$SPEC_MODEL" --arg task "${SPEC_TASK:0:1000}" \
    --arg mem "$mem" --arg cpu "$cpu" --arg work "$(kube_quantity "${SANDBOX_WORK_SIZE:-2g}")" \
    --arg memreq "$(kube_quantity "${SANDBOX_MEMORY_REQUEST:-512m}")" --arg cpureq "${SANDBOX_CPUS_REQUEST:-0.25}" \
    --arg sa "${SANDBOX_SERVICE_ACCOUNT:-}" --arg pullsecret "${SANDBOX_IMAGE_PULL_SECRET:-}" \
    --argjson deadline "$deadline" --argjson ttl "${SANDBOX_JOB_TTL:-3600}" --argjson env "$env_json" '
    {
      apiVersion: "batch/v1", kind: "Job",
      metadata: {
        name: $name, namespace: $ns,
        labels: {"mercury.sandbox": "1", "app.kubernetes.io/name": "mercury-sandbox", "app.kubernetes.io/part-of": "mercury"},
        annotations: {"mercury.repo": $repo, "mercury.branch": $branch, "mercury.model": $model, "mercury.task": $task}
      },
      spec: {
        backoffLimit: 0, ttlSecondsAfterFinished: $ttl, activeDeadlineSeconds: $deadline,
        template: {
          metadata: {labels: {"mercury.sandbox": "1", "app.kubernetes.io/name": "mercury-sandbox", "app.kubernetes.io/part-of": "mercury"}},
          spec: {
            restartPolicy: "Never",
            automountServiceAccountToken: false,
            enableServiceLinks: false,
            securityContext: {runAsNonRoot: true, runAsUser: 1000, runAsGroup: 1000, fsGroup: 1000, seccompProfile: {type: "RuntimeDefault"}},
            containers: [{
              name: "sandbox", image: $image, imagePullPolicy: "IfNotPresent",
              env: $env,
              envFrom: [{secretRef: {name: $name}}],
              securityContext: {readOnlyRootFilesystem: true, allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}},
              resources: {limits: {memory: $mem, cpu: $cpu}, requests: {memory: $memreq, cpu: $cpureq}},
              volumeMounts: [
                {name: "work", mountPath: "/work"},
                {name: "home", mountPath: "/home/agent"},
                {name: "tmp", mountPath: "/tmp"}
              ]
            }],
            volumes: [
              {name: "work", emptyDir: {medium: "Memory", sizeLimit: $work}},
              {name: "home", emptyDir: {medium: "Memory", sizeLimit: "512Mi"}},
              {name: "tmp", emptyDir: {medium: "Memory", sizeLimit: "256Mi"}}
            ]
          }
        }
      }
    }
    | if $sa != "" then .spec.template.spec.serviceAccountName = $sa else . end
    | if $pullsecret != "" then .spec.template.spec.imagePullSecrets = [{name: $pullsecret}] else . end')"

  # Secret first so the pod never waits on it, then the Job, then make the
  # Job own the Secret so garbage collection removes both together.
  jq -n --arg name "$SPEC_NAME" --arg ns "$ns" --argjson data "$secret_json" \
    '{apiVersion: "v1", kind: "Secret", metadata: {name: $name, namespace: $ns, labels: {"mercury.sandbox": "1"}}, type: "Opaque", stringData: $data}' |
    kc create -f - >/dev/null
  local uid
  uid="$(printf '%s' "$job" | kc create -f - -o jsonpath='{.metadata.uid}')" || {
    kc delete secret "$SPEC_NAME" --ignore-not-found >/dev/null
    die "could not create job $SPEC_NAME"
  }
  kc patch secret "$SPEC_NAME" --type merge -p "$(jq -nc --arg n "$SPEC_NAME" --arg u "$uid" \
    '{metadata: {ownerReferences: [{apiVersion: "batch/v1", kind: "Job", name: $n, uid: $u, blockOwnerDeletion: false}]}}')" >/dev/null

  log "started job $SPEC_NAME in $ns -> branch $SPEC_BRANCH  (mercury logs $SPEC_NAME | mercury kill $SPEC_NAME)"
  if [ "$SPEC_DETACH" -eq 1 ]; then
    printf '%s\n' "$SPEC_NAME"
    return 0
  fi
  # Foreground: follow the pod once it exists, then report how the Job ended.
  for _ in $(seq 1 120); do
    if kc logs -f "job/$SPEC_NAME" 2>/dev/null; then break; fi
    sleep 2
  done
  kc wait --for=condition=complete --timeout=10s "job/$SPEC_NAME" >/dev/null 2>&1 ||
    kc wait --for=condition=failed --timeout=10s "job/$SPEC_NAME" >/dev/null 2>&1 || true
  local rc=0
  if [ "$(kc get "job/$SPEC_NAME" -o jsonpath='{.status.succeeded}')" != "1" ]; then
    log "job $SPEC_NAME did not succeed (kubectl -n $ns describe job/$SPEC_NAME)"
    rc=1
  fi
  [ -n "${SPEC_GATEWAY_KEY:-}" ] && creds_revoke_gateway_key "$SPEC_GATEWAY_KEY"
  return "$rc"
}

backend_list_json() {
  kc get jobs -l mercury.sandbox=1 -o json | jq '[.items[] | {
      name: .metadata.name,
      status: (if (.status.succeeded // 0) > 0 then "succeeded"
               elif (.status.failed // 0) > 0 then "failed"
               elif (.status.active // 0) > 0 then "running"
               else "pending" end),
      started: (.status.startTime // .metadata.creationTimestamp),
      repo: (.metadata.annotations["mercury.repo"] // ""),
      branch: (.metadata.annotations["mercury.branch"] // ""),
      model: (.metadata.annotations["mercury.model"] // ""),
      task: (.metadata.annotations["mercury.task"] // ""),
      backend: "kubernetes"
    }] | sort_by(.started) | reverse'
}

backend_ps() {
  backend_list_json | jq -r '(["NAME","STATUS","BRANCH","REPO"] | @tsv), (.[] | [.name, .status, .branch, .repo] | @tsv)' | column -t -s "$(printf '\t')"
}

backend_logs() {
  local args=(--tail "$2")
  [ "$3" = "1" ] && args+=(-f)
  kc logs "${args[@]}" "job/$1"
}

backend_kill() { kc delete job "$1" --wait=false; }

backend_exec() {
  local name="$1"
  shift
  kc exec -it "job/$name" -- "$@"
}
