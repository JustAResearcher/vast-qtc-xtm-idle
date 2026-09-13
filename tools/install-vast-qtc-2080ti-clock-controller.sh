#!/usr/bin/env bash
set -Eeuo pipefail

CONTROLLER=/usr/local/sbin/vast-qtc-clock-controller
SERVICE=/etc/systemd/system/vast-qtc-clock-controller.service
CONFIG=/etc/default/vast-qtc-clock-controller
CORE_LOCK_MHZ=${CORE_LOCK_MHZ:-1750}
MEMORY_LOCK_MHZ=${MEMORY_LOCK_MHZ:-}
POWER_LIMIT_W=${POWER_LIMIT_W:-}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run this installer from the physical Ubuntu host's root shell." >&2
  exit 1
fi

for command_name in nvidia-smi docker systemctl grep; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    exit 1
  fi
done

if [[ ! "$CORE_LOCK_MHZ" =~ ^[0-9]+$ ]]; then
  echo "CORE_LOCK_MHZ must be a positive integer." >&2
  exit 1
fi
if [[ -n "$MEMORY_LOCK_MHZ" && ! "$MEMORY_LOCK_MHZ" =~ ^[0-9]+$ ]]; then
  echo "MEMORY_LOCK_MHZ must be empty or a positive integer." >&2
  exit 1
fi
if [[ -n "$POWER_LIMIT_W" && ! "$POWER_LIMIT_W" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "POWER_LIMIT_W must be empty or a positive number." >&2
  exit 1
fi

gpu_name=$(nvidia-smi -i 0 --query-gpu=name --format=csv,noheader | head -n 1)
if [[ "$gpu_name" != *"RTX 2080 Ti"* ]]; then
  echo "Refusing to install: GPU 0 is '$gpu_name', not an RTX 2080 Ti." >&2
  exit 1
fi

if [[ -n "$MEMORY_LOCK_MHZ" ]]; then
  echo "Locked memory clocks are not supported by this RTX 2080 Ti; existing settings were not changed." >&2
  exit 1
fi

DEFAULT_POWER_LIMIT_W=$(nvidia-smi -i 0 --query-gpu=power.default_limit --format=csv,noheader,nounits | head -n 1 | tr -d ' ')
if [[ ! "$DEFAULT_POWER_LIMIT_W" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Could not read the RTX 2080 Ti default power limit; existing settings were not changed." >&2
  exit 1
fi

install -d -m 0755 /usr/local/sbin

{
  printf 'CORE_LOCK_MHZ=%s\n' "$CORE_LOCK_MHZ"
  printf 'MEMORY_LOCK_MHZ=%s\n' "$MEMORY_LOCK_MHZ"
  printf 'POWER_LIMIT_W=%s\n' "$POWER_LIMIT_W"
  printf 'DEFAULT_POWER_LIMIT_W=%s\n' "$DEFAULT_POWER_LIMIT_W"
} >"$CONFIG"
chmod 0644 "$CONFIG"

cat >"$CONTROLLER" <<'CONTROLLER_EOF'
#!/usr/bin/env bash
set -uo pipefail

GPU_INDEX=0
OWNER_IMAGE='ghcr.io/justaresearcher/vast-qtc-xtm-idle@sha256:7f656407b2e71cdd1928ba1c38da6aae4e91b3fa24c9c773597570b94848b428'
OWNER_WORKER='mfarm-rig-881343'
POLL_SECONDS=3
STATE='unknown'

source /etc/default/vast-qtc-clock-controller

log() {
  printf '[vast-qtc-clock] %s\n' "$*"
}

reset_clocks() {
  nvidia-smi -i "$GPU_INDEX" --reset-gpu-clocks >/dev/null 2>&1 || true
  nvidia-smi -i "$GPU_INDEX" --reset-memory-clocks >/dev/null 2>&1 || true
  nvidia-smi -i "$GPU_INDEX" --power-limit="$DEFAULT_POWER_LIMIT_W" >/dev/null 2>&1 || true
  if [[ "$STATE" != 'stock' ]]; then
    log 'restored stock clocks and power limit'
  fi
  STATE='stock'
}

apply_owner_clocks() {
  nvidia-smi -i "$GPU_INDEX" --persistence-mode=1 >/dev/null 2>&1 || true
  nvidia-smi -i "$GPU_INDEX" --reset-gpu-clocks >/dev/null 2>&1 || true
  nvidia-smi -i "$GPU_INDEX" --reset-memory-clocks >/dev/null 2>&1 || true
  nvidia-smi -i "$GPU_INDEX" --power-limit="$DEFAULT_POWER_LIMIT_W" >/dev/null 2>&1 || true

  if ! nvidia-smi -i "$GPU_INDEX" --lock-gpu-clocks="$CORE_LOCK_MHZ,$CORE_LOCK_MHZ" >/dev/null 2>&1; then
    reset_clocks
    STATE='error'
    log "core clock apply failed; stock clocks restored and retry scheduled"
    return
  fi

  if [[ -n "$MEMORY_LOCK_MHZ" ]] \
      && ! nvidia-smi -i "$GPU_INDEX" --lock-memory-clocks="$MEMORY_LOCK_MHZ,$MEMORY_LOCK_MHZ" >/dev/null 2>&1; then
    reset_clocks
    STATE='error'
    log "memory clock apply failed; stock clocks restored and retry scheduled"
    return
  fi

  if [[ -n "$POWER_LIMIT_W" ]] \
      && ! nvidia-smi -i "$GPU_INDEX" --power-limit="$POWER_LIMIT_W" >/dev/null 2>&1; then
    reset_clocks
    STATE='error'
    log "power limit apply failed; stock clocks and power limit restored and retry scheduled"
    return
  fi

  STATE='owner'
  log "applied owner core lock ${CORE_LOCK_MHZ} MHz; memory remains stock; power limit ${POWER_LIMIT_W:-$DEFAULT_POWER_LIMIT_W} W"
}

is_gpu_container() {
  local container_id=$1 runtime requests devices environment
  runtime=$(docker inspect -f '{{.HostConfig.Runtime}}' "$container_id" 2>/dev/null || true)
  requests=$(docker inspect -f '{{json .HostConfig.DeviceRequests}}' "$container_id" 2>/dev/null || true)
  devices=$(docker inspect -f '{{json .HostConfig.Devices}}' "$container_id" 2>/dev/null || true)
  environment=$(docker inspect -f '{{json .Config.Env}}' "$container_id" 2>/dev/null || true)

  [[ "$runtime" == 'nvidia' \
    || "$requests" == *'gpu'* \
    || "$requests" == *'nvidia'* \
    || "$devices" == *'/dev/nvidia'* \
    || "$environment" == *'NVIDIA_VISIBLE_DEVICES'* ]]
}

owner_is_only_gpu_workload() {
  local container_id image command_line owner_count=0 other_gpu_count=0

  systemctl is-active --quiet docker || return 1
  docker info >/dev/null 2>&1 || return 1

  while IFS= read -r container_id; do
    [[ -n "$container_id" ]] || continue
    image=$(docker inspect -f '{{.Config.Image}}' "$container_id" 2>/dev/null || true)
    command_line=$(docker inspect -f '{{json .Config.Cmd}}' "$container_id" 2>/dev/null || true)

    if [[ "$image" == "$OWNER_IMAGE" && "$command_line" == *"$OWNER_WORKER"* ]]; then
      owner_count=$((owner_count + 1))
    elif is_gpu_container "$container_id"; then
      other_gpu_count=$((other_gpu_count + 1))
    fi
  done < <(docker ps --no-trunc --format '{{.ID}}' 2>/dev/null)

  [[ $owner_count -eq 1 && $other_gpu_count -eq 0 ]]
}

trap 'exit 0' INT TERM
trap 'reset_clocks' EXIT

while true; do
  if owner_is_only_gpu_workload; then
    if [[ "$STATE" != 'owner' ]]; then
      apply_owner_clocks
    fi
  elif [[ "$STATE" != 'stock' ]]; then
    reset_clocks
  fi
  sleep "$POLL_SECONDS"
done
CONTROLLER_EOF

chmod 0755 "$CONTROLLER"

cat >"$SERVICE" <<'SERVICE_EOF'
[Unit]
Description=Renter-aware Vast QTC clock controller
After=docker.service vastai.service nvidia-persistenced.service
Wants=docker.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/vast-qtc-clock-controller
Restart=always
RestartSec=3
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF

chmod 0644 "$SERVICE"
systemctl daemon-reload
systemctl enable vast-qtc-clock-controller.service
systemctl restart vast-qtc-clock-controller.service

if ! systemctl is-active --quiet vast-qtc-clock-controller.service; then
  echo "Controller failed to start:" >&2
  journalctl -u vast-qtc-clock-controller.service -n 30 --no-pager >&2
  exit 1
fi

echo "Installed and running for: $gpu_name"
echo "Requested owner clocks: core ${CORE_LOCK_MHZ} MHz, memory ${MEMORY_LOCK_MHZ:-stock}"
echo "Requested owner power limit: ${POWER_LIMIT_W:-$DEFAULT_POWER_LIMIT_W} W"
systemctl status vast-qtc-clock-controller.service --no-pager --lines=8
nvidia-smi -i 0 --query-gpu=name,clocks.current.graphics,clocks.current.memory,power.limit,power.draw,temperature.gpu --format=csv,noheader
