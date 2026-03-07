import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const scriptPath = path.join(repoRoot, "scripts", "sync-runtime-config.mjs");
const tempDirs: string[] = [];

function createStateDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-sync-runtime-config-"));
  tempDirs.push(dir);
  return dir;
}

function readConfig(configPath: string) {
  return JSON.parse(fs.readFileSync(configPath, "utf8")) as {
    agents?: {
      defaults?: {
        model?: {
          primary?: string;
          fallbacks?: string[];
        };
        thinkingDefault?: string;
      };
    };
  };
}

function runSyncRuntimeConfig(env: NodeJS.ProcessEnv) {
  execFileSync(process.execPath, [scriptPath], {
    cwd: repoRoot,
    env: { ...process.env, ...env },
    encoding: "utf8",
  });
}

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

describe("sync-runtime-config", () => {
  it("defaults OPENAI_API_KEY deployments to the current Codex model", () => {
    const stateDir = createStateDir();
    const configPath = path.join(stateDir, "openclaw.json");
    fs.writeFileSync(configPath, "{}\n");

    runSyncRuntimeConfig({
      OPENCLAW_STATE_DIR: stateDir,
      OPENCLAW_CONFIG_FILE: configPath,
      OPENAI_API_KEY: "test-openai-key",
    });

    const cfg = readConfig(configPath);
    expect(cfg.agents?.defaults?.model?.primary).toBe("openai-codex/gpt-5.4");
  });

  it("lets deployment env override model.primary and thinkingDefault", () => {
    const stateDir = createStateDir();
    const configPath = path.join(stateDir, "openclaw.json");
    fs.writeFileSync(
      configPath,
      `${JSON.stringify(
        {
          agents: {
            defaults: {
              model: {
                primary: "openai-codex/gpt-5.3-codex",
              },
            },
          },
        },
        null,
        2,
      )}\n`,
    );

    runSyncRuntimeConfig({
      OPENCLAW_STATE_DIR: stateDir,
      OPENCLAW_CONFIG_FILE: configPath,
      OPENAI_API_KEY: "test-openai-key",
      OPENCLAW_MODEL_PRIMARY: "openai-codex/gpt-5.4",
      OPENCLAW_THINKING_DEFAULT: "xhigh",
    });

    const cfg = readConfig(configPath);
    expect(cfg.agents?.defaults?.model?.primary).toBe("openai-codex/gpt-5.4");
    expect(cfg.agents?.defaults?.thinkingDefault).toBe("xhigh");
  });
});
