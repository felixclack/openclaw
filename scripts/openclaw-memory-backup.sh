#!/usr/bin/env bash
set -euo pipefail

# OpenClaw memory backup helper.
#
# Mirrors memory markdown files + core context files from the active workspace
# to a backup location (optionally git-sync + optional S3 sync).
#
# Environment variables:
#   OPENCLAW_WORKSPACE              Workspace root (default: /data/workspace)
#   OPENCLAW_MEMORY_BACKUP_ROOT     Backup root (default: /data/openclaw-memory-backup)
#   OPENCLAW_MEMORY_BACKUP_GIT_SYNC Set to 1 to commit/push in backup repo if .git exists
#   OPENCLAW_MEMORY_BACKUP_S3_URI   Optional S3 URI mirror target (s3://bucket/path)

WORKSPACE="${OPENCLAW_WORKSPACE:-/data/workspace}"
BACKUP_ROOT="${OPENCLAW_MEMORY_BACKUP_ROOT:-/data/openclaw-memory-backup}"
CORE_DIR="${BACKUP_ROOT}/core"
DAILY_DIR="${BACKUP_ROOT}/daily"
META_DIR="${BACKUP_ROOT}/meta"

mkdir -p "$CORE_DIR" "$DAILY_DIR" "$META_DIR"

if [ ! -d "$WORKSPACE" ]; then
  echo "ERROR: workspace does not exist: $WORKSPACE" >&2
  exit 1
fi

# 1) Mirror daily markdown notes from memory/*.md
if [ -d "$WORKSPACE/memory" ]; then
  find "$DAILY_DIR" -mindepth 1 -delete
  while IFS= read -r -d  src; do
    rel="${src#"$WORKSPACE/memory/"}"
    dst="${DAILY_DIR}/${rel}"
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
  done < <(find "$WORKSPACE/memory" -type f -name *.md -print0)
fi

# 2) Mirror core context files used for always-on memory/persona
for file in MEMORY.md SOUL.md USER.md IDENTITY.md AGENTS.md; do
  src="${WORKSPACE}/${file}"
  dst="${CORE_DIR}/${file}"
  if [ -f "$src" ]; then
    cp -f "$src" "$dst"
  else
    rm -f "$dst"
  fi
done

# 3) Metadata + checksums
{
  echo "synced_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "workspace=${WORKSPACE}"
} > "${META_DIR}/last-sync.env"

if command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$BACKUP_ROOT"
    find core daily -type f -name *.md -print0 | sort -z | xargs -0 sha256sum > "${META_DIR}/checksums.sha256" || true
  )
fi

# 4) Optional git sync in backup root
if [ "${OPENCLAW_MEMORY_BACKUP_GIT_SYNC:-0}" = "1" ] && [ -d "${BACKUP_ROOT}/.git" ]; then
  cd "$BACKUP_ROOT"
  git config --global --add safe.directory "$BACKUP_ROOT" >/dev/null 2>&1 || true
  if git remote get-url origin >/dev/null 2>&1; then
    git pull --rebase --autostash origin main >/dev/null 2>&1 || true
  fi
  if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "backup: openclaw memory mirror $(date -u +%Y-%m-%dT%H:%M:%SZ)" --no-verify >/dev/null 2>&1 || true
    if git remote get-url origin >/dev/null 2>&1; then
      git push origin main >/dev/null 2>&1 || true
    fi
  fi
fi

# 5) Optional S3 mirror
if [ -n "${OPENCLAW_MEMORY_BACKUP_S3_URI:-}" ]; then
  if command -v aws >/dev/null 2>&1; then
    aws s3 sync "${BACKUP_ROOT}/" "${OPENCLAW_MEMORY_BACKUP_S3_URI}/" --delete >/dev/null
  else
    echo "WARN: OPENCLAW_MEMORY_BACKUP_S3_URI set but aws CLI not found; skipping S3 sync" >&2
  fi
fi

echo "OK: openclaw-memory-backup complete"
