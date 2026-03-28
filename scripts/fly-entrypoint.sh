#!/bin/bash
# Minimal Fly.io entrypoint: persistent state + Tailscale
set -e

PERSISTENT_HOME="/data/home"

# --- Persistent home directories ---
mkdir -p "$PERSISTENT_HOME/.config"

symlink_persistent() {
    local src="$1" dst="$2"
    if [ -e "$src" ] && [ ! -L "$src" ]; then rm -rf "$src"; fi
    mkdir -p "$(dirname "$src")"
    if [ ! -L "$src" ]; then
        ln -sf "$dst" "$src"
        echo "[entrypoint] Linked $src -> $dst"
    fi
}

# Persist config directories across restarts
mkdir -p "$PERSISTENT_HOME/.config/gh"
symlink_persistent "$HOME/.config/gh" "$PERSISTENT_HOME/.config/gh"

if [ -f "$PERSISTENT_HOME/.gitconfig" ]; then
    symlink_persistent "$HOME/.gitconfig" "$PERSISTENT_HOME/.gitconfig"
fi

if [ -d "$PERSISTENT_HOME/.ssh" ] && [ "$(ls -A "$PERSISTENT_HOME/.ssh" 2>/dev/null)" ]; then
    symlink_persistent "$HOME/.ssh" "$PERSISTENT_HOME/.ssh"
    chmod 700 "$PERSISTENT_HOME/.ssh"
    chmod 600 "$PERSISTENT_HOME/.ssh"/* 2>/dev/null || true
fi

# --- One-shot config reset ---
if [ "${RESET_CONFIG}" = "true" ] || [ "${RESET_CONFIG}" = "1" ]; then
    rm -f "${OPENCLAW_STATE_DIR:-/data}/openclaw.json"
    echo "[entrypoint] Config reset"
fi

# --- Tailscale (entirely non-fatal) ---
if [ -n "$TAILSCALE_AUTHKEY" ] && command -v tailscaled >/dev/null 2>&1; then
    (
        mkdir -p /data/tailscale
        tailscaled \
            --state=/data/tailscale/tailscaled.state \
            --socket=/var/run/tailscale/tailscaled.sock \
            --tun=userspace-networking \
            --socks5-server=localhost:1055 \
            --outbound-http-proxy-listen=localhost:1056 &
        sleep 3
        tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname="clawdbot-fly" --accept-routes
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
        echo "[entrypoint] Tailscale: ${TAILSCALE_IP:-pending}"
        tailscale serve --bg --https 443 http://localhost:3000 2>/dev/null || true
    ) || echo "[entrypoint] Warning: Tailscale setup failed (non-fatal)"
fi

echo "[entrypoint] Ready"
exec "$@"
