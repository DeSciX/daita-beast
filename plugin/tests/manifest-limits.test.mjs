// The limits claude.ai applies when it syncs a marketplace (the CLI's `claude plugin validate` does not check them):
// a plugin description of at most 500 characters, and skill and agent descriptions with no angle brackets. The
// platform's owner of these rules is descix-cli lib/core/ClaudePluginLimits.js (CLAUDE_PLUGIN_LIMITS); keep these equal.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const plugin = join(dirname(fileURLToPath(import.meta.url)), '..');

function description(file) {
  const m = readFileSync(file, 'utf8').match(/^---\n([\s\S]*?)\n---/);
  if (!m) return null;
  const d = m[1].match(/^description:\s*([\s\S]*?)(?=^[\w-]+:|$(?![\s\S]))/m);
  // A YAML block indicator (description: >, |, >-, |-) is syntax, not text: it is not counted (the platform's
  // ClaudePluginLimits does the same).
  return d ? d[1].trim().replace(/^[>|][+-]?\s*\n/, '') : null;
}

test('plugin description is at most 500 characters', () => {
  const d = JSON.parse(readFileSync(join(plugin, '.claude-plugin/plugin.json'), 'utf8')).description;
  assert.ok(d.length <= 500, `plugin.json description is ${d.length} characters`);
});

test('skill and agent descriptions carry no angle brackets', () => {
  const files = [];
  for (const s of readdirSync(join(plugin, 'skills'))) {
    const f = join(plugin, 'skills', s, 'SKILL.md');
    if (existsSync(f)) files.push(f);
  }
  for (const a of readdirSync(join(plugin, 'agents'))) if (a.endsWith('.md')) files.push(join(plugin, 'agents', a));
  const bad = files.filter((f) => /[<>]/.test(description(f) ?? '')).map((f) => f.slice(plugin.length + 1));
  assert.deepEqual(bad, [], `descriptions with angle brackets: ${bad.join(', ')}`);
});
