#!/bin/bash
set -euo pipefail

STATE_DIR="${OPENCLAW_STATE_DIR:-/data}"
APP_DIR="${OPENCLAW_APP_DIR:-/app}"
NODE_UID="${OPENCLAW_RUNTIME_UID:-1000}"
NODE_GID="${OPENCLAW_RUNTIME_GID:-1000}"
NODE_HOME="${OPENCLAW_RUNTIME_HOME:-/home/node}"
GBRAIN_PARENT_HOME="${GBRAIN_HOME:-$STATE_DIR/gbrain}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-3000}"
GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-lan}"

export GBRAIN_HOME="$GBRAIN_PARENT_HOME"

if [ "$(id -u)" = "0" ]; then
  install -d -m 700 -o "$NODE_UID" -g "$NODE_GID" "$NODE_HOME"
  install -d -m 700 -o "$NODE_UID" -g "$NODE_GID" "$STATE_DIR"
  install -d -m 700 -o "$NODE_UID" -g "$NODE_GID" "$GBRAIN_PARENT_HOME"

  find "$STATE_DIR" -maxdepth 1 -type f -name '*.json' \
    -exec chown "$NODE_UID:$NODE_GID" {} + 2>/dev/null || true

  for dir in \
    agents \
    bin \
    canvas \
    codex-cli \
    credentials \
    credentials/gh \
    cron \
    devices \
    flows \
    gbrain \
    identity \
    logs \
    memory \
    sessions \
    state \
    tasks \
    telegram \
    workspace
  do
    if [ -d "$STATE_DIR/$dir" ]; then
      chown -R "$NODE_UID:$NODE_GID" "$STATE_DIR/$dir" 2>/dev/null || true
    fi
  done

  cd "$APP_DIR"
  export HOME="$NODE_HOME"
  if [ "$#" -eq 0 ]; then
    set -- node dist/index.js gateway --allow-unconfigured --port "$GATEWAY_PORT" --bind "$GATEWAY_BIND"
  fi

  if command -v setpriv >/dev/null 2>&1; then
    exec setpriv --reuid="$NODE_UID" --regid="$NODE_GID" --init-groups "$@"
  fi

  exec su -s /bin/sh node -c 'cd "$1" && shift && exec "$@"' sh "$APP_DIR" "$@"
fi

cd "$APP_DIR"
if [ "$(id -u)" = "$NODE_UID" ] && [ "${HOME:-}" = "/root" ]; then
  export HOME="$NODE_HOME"
fi
if [ "$#" -eq 0 ]; then
  set -- node dist/index.js gateway --allow-unconfigured --port "$GATEWAY_PORT" --bind "$GATEWAY_BIND"
fi
exec "$@"
