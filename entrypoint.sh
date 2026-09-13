#!/usr/bin/env bash
set -Eeuo pipefail

QTC_WALLET=${1:?QTC wallet is required}
XTM_WALLET=${2:?XTM wallet is required}
WORKER=${3:-${HOSTNAME:-vast-idle}}

QTC_POOL=${QTC_POOL:-stratum+tcp://qtc-us.kryptex.network:7049}
XTM_POOL=${XTM_POOL:-xtm-rx-us.kryptex.network:7038}

cat >/tmp/xmrig-config.json <<EOF
{
  "autosave": false,
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "hw-aes": null,
    "priority": null,
    "memory-pool": false,
    "asm": true,
    "rx": [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14]
  },
  "opencl": false,
  "cuda": false,
  "pools": [{
    "algo": "rx/0",
    "url": "${XTM_POOL}",
    "user": "${XTM_WALLET}/${WORKER}",
    "pass": "x",
    "keepalive": true,
    "tls": false
  }]
}
EOF

srb_pid=''
xmrig_pid=''

cleanup() {
  local pid
  trap - EXIT INT TERM
  for pid in "$srb_pid" "$xmrig_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill -INT "$pid" 2>/dev/null || true
    fi
  done
  for _ in 1 2 3 4 5 6; do
    if { [[ -z "$srb_pid" ]] || ! kill -0 "$srb_pid" 2>/dev/null; } \
      && { [[ -z "$xmrig_pid" ]] || ! kill -0 "$xmrig_pid" 2>/dev/null; }; then
      break
    fi
    sleep 1
  done
  for pid in "$srb_pid" "$xmrig_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  wait 2>/dev/null || true
  nvidia-smi -i 0 --reset-gpu-clocks >/dev/null 2>&1 || true
  nvidia-smi -i 0 --reset-memory-clocks >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

env -u LD_PRELOAD -u LD_PRELOAD_ENV SRBMiner-MULTI \
  --background \
  --disable-cpu \
  --algorithm quantus \
  --pool "$QTC_POOL" \
  --wallet "$QTC_WALLET" \
  --worker "$WORKER" \
  --password x \
  --tls false \
  --gpu-id 0 \
  --gpu-reset-oc \
  --gpu-coffset0 250 \
  --gpu-cclock0 1750 \
  --gpu-mclock0 810 \
  --oc-coffset-delayed &
srb_pid=$!

xmrig --config=/tmp/xmrig-config.json &
xmrig_pid=$!

set +e
wait -n "$srb_pid" "$xmrig_pid"
first_exit=$?
set -e

if ! kill -0 "$srb_pid" 2>/dev/null; then
  echo "[idle-mining] SRBMiner exited with code ${first_exit}" >&2
fi
if ! kill -0 "$xmrig_pid" 2>/dev/null; then
  echo "[idle-mining] XMRig exited with code ${first_exit}" >&2
fi

# Keep the container alive briefly so Vast can retain the first-failure logs.
sleep 15
exit "$first_exit"
