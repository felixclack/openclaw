---
summary: "Harden OpenClaw memory reliability with pre-compaction flush, 5-minute backup mirror, and nightly rollup"
read_when:
  - You want memory to survive compaction and host restarts
  - You want an operational memory pipeline for production
title: "Memory reliability pipeline"
---

# Memory reliability pipeline

This playbook implements a practical **three-layer memory reliability pipeline**:

1. **Pre-compaction memory flush** (`agents.defaults.compaction.memoryFlush`)
2. **Frequent off-host backup mirror** of workspace memory files (~5 minutes)
3. **Nightly curation rollup** into `MEMORY.md` (dedupe + superseded cleanup)

Use this when you want memory continuity across long chats, compaction cycles,
and infrastructure restarts.

## 1) Enable pre-compaction memory flush

Set memory flush in config so OpenClaw stores durable notes before compaction.

```json5
{
  "agents": {
    "defaults": {
      "compaction": {
        "mode": "safeguard",
        "memoryFlush": {
          "enabled": true,
          "softThresholdTokens": 4000,
          "systemPrompt": "Session nearing compaction. Store durable memories now.",
          "prompt": "Write durable facts/preferences/decisions to MEMORY.md and short run-state to memory/YYYY-MM-DD.md. Dedupe against existing notes. Reply with NO_REPLY unless clarification is required."
        }
      }
    }
  }
}
```

## 2) Configure 5-minute backup mirror

Use `scripts/openclaw-memory-backup.sh` to mirror:

- `memory/*.md` → backup `daily/`
- `MEMORY.md`, `SOUL.md`, `USER.md`, `IDENTITY.md`, `AGENTS.md` → backup `core/`

### Script options

- `OPENCLAW_WORKSPACE` (default: `/data/workspace`)
- `OPENCLAW_MEMORY_BACKUP_ROOT` (default: `/data/openclaw-memory-backup`)
- `OPENCLAW_MEMORY_BACKUP_GIT_SYNC=1` to commit/push if backup root is a git repo
- `OPENCLAW_MEMORY_BACKUP_S3_URI=s3://...` for optional off-host S3 mirror

### Cron tool payload (isolated, every 5 minutes)

```json
{
  "name": "OpenClaw memory mirror backup (every 5m)",
  "sessionTarget": "isolated",
  "schedule": { "kind": "every", "everyMs": 300000 },
  "payload": {
    "kind": "agentTurn",
    "thinking": "low",
    "timeoutSeconds": 120,
    "message": "Run memory backup. Do exactly one command: bash -lc scripts/openclaw-memory-backup.sh. If output includes ERROR/WARN or the command fails, alert with the short failure + next step. Otherwise send nothing."
  },
  "delivery": { "mode": "none", "bestEffort": true }
}
```

## 3) Configure nightly curation rollup

Nightly rollup keeps `MEMORY.md` high-signal and removes stale duplicates.

### Cron tool payload (isolated, nightly)

```json
{
  "name": "OpenClaw nightly memory rollup",
  "sessionTarget": "isolated",
  "schedule": { "kind": "cron", "expr": "15 1 * * *", "tz": "UTC" },
  "payload": {
    "kind": "agentTurn",
    "thinking": "low",
    "timeoutSeconds": 240,
    "message": "Read /data/workspace/MEMORY.md and up to the last 3 daily files in /data/workspace/memory/*.md. Update MEMORY.md with durable facts/preferences/decisions only, dedupe repeated items, remove superseded statements, and commit only MEMORY.md with message: memory: nightly rollup when changed. Reply NO_REPLY on success; only speak if there is an error."
  },
  "delivery": { "mode": "none", "bestEffort": true }
}
```

## Backend guidance: SQLite vs QMD

- **Default recommendation**: built-in SQLite memory + remote embeddings (`memory-core`) is usually sufficient and lower operational overhead.
- **Use QMD** when you need fully-local retrieval/reranking and have enough hardware/runtime budget.

See also: [Memory](/concepts/memory), [Cron jobs](/automation/cron-jobs)
