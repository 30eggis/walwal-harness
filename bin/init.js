#!/usr/bin/env node

/**
 * walwal-harness initializer
 *
 * Usage:
 *   npx walwal-harness          # Interactive init
 *   npx walwal-harness --auto   # Auto init (postinstall)
 *   npx walwal-harness --force  # Force reinit
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PKG_ROOT = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const subcommand = args.find(a => !a.startsWith('-')) || null;
const subcommandArgs = args.filter(a => !a.startsWith('-') && a !== subcommand);
const isAuto = args.includes('--auto');
const isForce = args.includes('--force');
const isHelp = args.includes('--help') || args.includes('-h');

// ─────────────────────────────────────────
// Resolve project root
// ─────────────────────────────────────────
// During `npm install` postinstall, cwd is the dependency's own directory
// inside node_modules, NOT the consumer project root.
// We detect this and walk up to find the actual project root.
function resolveProjectRoot() {
  let cwd = process.cwd();

  // If we're running inside node_modules, walk up to the project root
  // e.g. /project/node_modules/@walwal-harness/cli → /project
  const nmIndex = cwd.indexOf(path.sep + 'node_modules' + path.sep);
  if (nmIndex !== -1) {
    return cwd.substring(0, nmIndex);
  }

  // Also handle case where cwd IS a node_modules child (no trailing sep match)
  if (cwd.includes(`${path.sep}node_modules`)) {
    const parts = cwd.split(path.sep);
    const nmIdx = parts.indexOf('node_modules');
    if (nmIdx > 0) {
      return parts.slice(0, nmIdx).join(path.sep);
    }
  }

  // npx or direct invocation — cwd is the project root
  return cwd;
}

const PROJECT_ROOT = resolveProjectRoot();
const HARNESS_DIR = path.join(PROJECT_ROOT, '.harness');
const CLAUDE_SKILLS_DIR = path.join(PROJECT_ROOT, '.claude', 'skills');

// ─────────────────────────────────────────
// Utility
// ─────────────────────────────────────────
function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function copyFile(src, dest) {
  ensureDir(path.dirname(dest));
  fs.copyFileSync(src, dest);
}

function copyDir(src, dest) {
  ensureDir(dest);
  const entries = fs.readdirSync(src, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      copyFile(srcPath, destPath);
    }
  }
}

function fileExists(p) {
  return fs.existsSync(p);
}

function log(msg) {
  console.log(`[walwal-harness] ${msg}`);
}

// ─────────────────────────────────────────
// First-install migration — extract Convention/Gotcha-shaped sections from
// existing CLAUDE.md / AGENTS.md into .harness/conventions and .harness/gotchas.
// Conservative: only triggers when these docs are NOT already harness-scaffolded
// (detected by IA-MAP tags like "[BE]" or "[HARNESS]").
// ─────────────────────────────────────────
function migrateExistingDocs() {
  // Match heading titles. Use (?=\s|$) instead of \b — Korean chars are
  // not "word" in JS regex, so \b produces inconsistent matches.
  const CONVENTION_HEADINGS = /^#{1,4}\s+(Conventions?|Coding Standards?|Style Guide|Rules|Guidelines|Best Practices|Do's and Don'ts|규칙|하우스 스타일|명명 규칙|코딩 규칙|코드 스타일)(?=[\s:]|$)/im;
  const GOTCHA_HEADINGS = /^#{1,4}\s+(Gotchas?|Anti[- ]?patterns?|Don'?ts?|Avoid|Pitfalls?|주의사항|금지사항|실수|함정|안티[- ]?패턴)(?=[\s:]|$)/im;
  const HARNESS_SIGNATURE = /\[(BE|FE|HARNESS|META|INFRA|ROOT)\]|walwal-harness|harness-dispatcher/;

  const candidates = [
    path.join(PROJECT_ROOT, 'CLAUDE.md'),
    path.join(PROJECT_ROOT, 'AGENTS.md')
  ];

  const report = [];
  const extractedConv = { counter: 0, byScope: {} };
  const extractedGotcha = { counter: 0, byAgent: {} };

  const scopeFor = (body) => {
    const b = body.toLowerCase();
    if (/\b(backend|api|nestjs|controller|dto|service|msa|repository)\b/.test(b)) return 'generator-backend';
    if (/\b(frontend|react|next\.?js|ui|component|tsx|tailwind|hook)\b/.test(b)) return 'generator-frontend';
    if (/\b(planner|plan\.md|sprint|feature-list|api-contract)\b/.test(b)) return 'planner';
    if (/\b(playwright|e2e|functional test)\b/.test(b)) return 'evaluator-functional';
    if (/\b(visual|layout|screenshot|a11y|accessibility|responsive)\b/.test(b)) return 'evaluator-visual';
    if (/\b(code quality|lint|tsc|architecture|typescript strict)\b/.test(b)) return 'evaluator-code-quality';
    return 'shared';
  };

  const appendEntry = (filePath, id, kind, title, body, source) => {
    const existing = fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
    const entry = [
      ``,
      `### [${id}] ${title}`,
      `- **Date**: ${new Date().toISOString().split('T')[0]}`,
      `- **Source**: ${source} (migrated)`,
      ``,
      body.trim(),
      ``
    ].join('\n');
    fs.writeFileSync(filePath, existing.replace(/\s*$/, '') + '\n' + entry + '\n');
  };

  for (const docPath of candidates) {
    if (!fileExists(docPath)) continue;
    const content = fs.readFileSync(docPath, 'utf8');
    if (HARNESS_SIGNATURE.test(content)) {
      // Already a harness-managed doc — skip
      continue;
    }

    // Backup
    const backupPath = path.join(HARNESS_DIR, 'archive', `pre-harness-${path.basename(docPath)}.bak`);
    fs.writeFileSync(backupPath, content);
    report.push(`Backed up: ${docPath} → ${backupPath}`);

    // Split by top-level and H2 headings to get sections
    // Simple approach: find heading lines, slice until next heading of same-or-higher level
    const lines = content.split('\n');
    const sections = [];
    let current = null;
    lines.forEach((line, idx) => {
      const m = /^(#{1,4})\s+(.+?)\s*$/.exec(line);
      if (m) {
        if (current) sections.push(current);
        current = { level: m[1].length, title: m[2], startLine: idx + 1, endLine: idx + 1, body: [] };
      } else if (current) {
        current.body.push(line);
        current.endLine = idx + 1;
      }
    });
    if (current) sections.push(current);

    for (const sec of sections) {
      const header = `${'#'.repeat(sec.level)} ${sec.title}`;
      const isConv = CONVENTION_HEADINGS.test(header);
      const isGotcha = GOTCHA_HEADINGS.test(header);
      if (!isConv && !isGotcha) continue;
      const body = sec.body.join('\n').trim();
      if (!body) continue;

      const sourceRef = `${path.basename(docPath)}:${sec.startLine}-${sec.endLine}`;

      if (isConv) {
        const scope = scopeFor(sec.title + '\n' + body);
        extractedConv.counter += 1;
        const id = `C-${String(extractedConv.counter).padStart(3, '0')}`;
        const target = path.join(HARNESS_DIR, 'conventions', `${scope}.md`);
        appendEntry(target, id, 'convention', sec.title, body, sourceRef);
        extractedConv.byScope[scope] = (extractedConv.byScope[scope] || 0) + 1;
        report.push(`[${id}] "${sec.title}" → conventions/${scope}.md  (from ${sourceRef})`);
      } else {
        const scope = scopeFor(sec.title + '\n' + body);
        const agent = scope === 'shared' ? 'planner' : scope;  // default shared-gotchas to planner
        extractedGotcha.counter += 1;
        const id = `G-${String(extractedGotcha.counter).padStart(3, '0')}`;
        const target = path.join(HARNESS_DIR, 'gotchas', `${agent}.md`);
        appendEntry(target, id, 'gotcha', sec.title, body, sourceRef);
        extractedGotcha.byAgent[agent] = (extractedGotcha.byAgent[agent] || 0) + 1;
        report.push(`[${id}] "${sec.title}" → gotchas/${agent}.md  (from ${sourceRef})`);
      }
    }
  }

  if (report.length === 0) return;

  const reportPath = path.join(HARNESS_DIR, 'MIGRATION_REPORT.md');
  const reportContent = [
    `# Walwal-Harness Migration Report`,
    ``,
    `Generated on first install at ${new Date().toISOString()}.`,
    ``,
    `## Summary`,
    ``,
    `- Conventions extracted: ${extractedConv.counter}`,
    `- Gotchas extracted: ${extractedGotcha.counter}`,
    ``,
    `## Manual Review Required`,
    ``,
    `Migration is heuristic (keyword-based). Please review each extracted entry:`,
    `- Verify scope assignment is correct`,
    `- Split entries into smaller atomic rules if appropriate`,
    `- Adjust wording to positive-rule form for conventions, negative/anti-pattern form for gotchas`,
    ``,
    `## Entries`,
    ``,
    ...report.map(r => `- ${r}`),
    ``,
    `## Backups`,
    ``,
    `Original documents were preserved in \`.harness/archive/pre-harness-*.md.bak\`.`,
    ``
  ].join('\n');
  fs.writeFileSync(reportPath, reportContent);
  log(`Migration: ${extractedConv.counter} convention(s), ${extractedGotcha.counter} gotcha(s) extracted.`);
  log(`Migration report: ${reportPath}`);
}

// ─────────────────────────────────────────
// 1. .harness/ scaffolding
// ─────────────────────────────────────────
function scaffoldHarness() {
  log('Scaffolding .harness/ directory...');

  // Detect first install BEFORE ensureDir creates the root
  const isFirstInstall = !fs.existsSync(HARNESS_DIR);

  // Core directories
  ensureDir(path.join(HARNESS_DIR, 'actions'));
  ensureDir(path.join(HARNESS_DIR, 'archive'));
  ensureDir(path.join(HARNESS_DIR, 'gotchas'));
  ensureDir(path.join(HARNESS_DIR, 'conventions'));

  // Copy gotchas — preserve any existing file that has accumulated entries.
  // Dispatcher appends `### [G-NNN] ...` entries directly; we must NEVER overwrite
  // a file that has such entries, or user learning history is lost.
  const gotchasSrc = path.join(PKG_ROOT, 'gotchas');
  if (fs.existsSync(gotchasSrc)) {
    const ENTRY_PATTERN = /^### \[G-\d+\]/m;  // Gotcha entry heading
    const CUSTOM_MARKER = '## Custom Gotchas'; // Legacy marker still supported
    const files = fs.readdirSync(gotchasSrc);
    for (const file of files) {
      const destPath = path.join(HARNESS_DIR, 'gotchas', file);
      const srcPath = path.join(gotchasSrc, file);
      if (!fileExists(destPath)) {
        copyFile(srcPath, destPath);
        continue;
      }
      if (!file.endsWith('.md')) continue;

      const existing = fs.readFileSync(destPath, 'utf8');
      const hasEntries = ENTRY_PATTERN.test(existing);
      const hasCustomSection = existing.indexOf(CUSTOM_MARKER) !== -1;

      if (hasEntries || hasCustomSection) {
        // User has accumulated data — DO NOT overwrite. Skip silently.
        // README.md is the only exception (system doc, regenerated below).
        if (file === 'README.md') {
          copyFile(srcPath, destPath);
        }
        continue;
      }

      // File exists but is just the scaffold template — safe to refresh
      copyFile(srcPath, destPath);
    }
  }

  // Copy conventions — mirror gotchas preservation: never overwrite files with
  // accumulated `### [C-NNN]` entries.
  const conventionsSrc = path.join(PKG_ROOT, 'conventions');
  if (fs.existsSync(conventionsSrc)) {
    const CONV_ENTRY = /^### \[C-\d+\]/m;
    const files = fs.readdirSync(conventionsSrc);
    for (const file of files) {
      const destPath = path.join(HARNESS_DIR, 'conventions', file);
      const srcPath = path.join(conventionsSrc, file);
      if (!fileExists(destPath)) {
        copyFile(srcPath, destPath);
        continue;
      }
      if (!file.endsWith('.md')) continue;
      const existing = fs.readFileSync(destPath, 'utf8');
      if (CONV_ENTRY.test(existing)) {
        if (file === 'README.md') copyFile(srcPath, destPath);
        continue;
      }
      copyFile(srcPath, destPath);
    }
  }

  // First-install migration: extract Convention/Gotcha-shaped sections from
  // existing CLAUDE.md / AGENTS.md and copy into the hierarchical stores.
  if (isFirstInstall) {
    try {
      migrateExistingDocs();
    } catch (e) {
      log('WARNING: migration failed — ' + e.message);
    }
  }

  // Copy templates as initial files
  const templateMap = {
    'progress.json.template': path.join(HARNESS_DIR, 'progress.json'),
  };

  const templatesDir = path.join(PKG_ROOT, 'assets', 'templates');
  if (fs.existsSync(templatesDir)) {
    for (const [template, dest] of Object.entries(templateMap)) {
      const src = path.join(templatesDir, template);
      if (fs.existsSync(src) && (!fileExists(dest) || isForce)) {
        let content = fs.readFileSync(src, 'utf8');
        content = content.replace(/\{\{DATE\}\}/g, new Date().toISOString().split('T')[0]);
        fs.writeFileSync(dest, content);
      }
    }
  }

  // Migrate progress.json v1 → v2 (add mode + team_state fields)
  const progressPath = path.join(HARNESS_DIR, 'progress.json');
  if (fileExists(progressPath)) {
    try {
      const progress = JSON.parse(fs.readFileSync(progressPath, 'utf8'));
      if (!progress.version || progress.version < 2) {
        progress.version = 2;
        progress.mode = progress.mode || 'solo';
        if (!progress.team_state) {
          progress.team_state = { active_teams: 0, paused_at: null, resume_from: null };
        }
        fs.writeFileSync(progressPath, JSON.stringify(progress, null, 2) + '\n');
        log('progress.json migrated to v2 (mode + team_state added)');
      }
      if (progress.version < 3) {
        progress.version = 3;
        if (!progress.dispatch) {
          progress.dispatch = { counter: 0, id: null };
        }
        fs.writeFileSync(progressPath, JSON.stringify(progress, null, 2) + '\n');
        log('progress.json migrated to v3 (dispatch counter added)');
      }
    } catch (e) {
      log('WARNING: Could not migrate progress.json');
    }
  }

  // config.json — ALWAYS update (harness system file, not user data)
  // But preserve user's custom settings (pre_eval_gate.frontend_cwd, behavior, etc.)
  const configSrc = path.join(PKG_ROOT, 'assets', 'templates', 'config.json');
  const configDest = path.join(HARNESS_DIR, 'config.json');
  if (fs.existsSync(configSrc)) {
    if (fileExists(configDest) && !isForce) {
      // Merge: keep user's customizations, update harness structure
      try {
        const existing = JSON.parse(fs.readFileSync(configDest, 'utf8'));
        const template = JSON.parse(fs.readFileSync(configSrc, 'utf8'));
        // Preserve user customizations
        const userPreserve = {
          behavior: existing.behavior,
          'flow.pre_eval_gate.frontend_cwd': existing?.flow?.pre_eval_gate?.frontend_cwd,
          'flow.pre_eval_gate.backend_cwd': existing?.flow?.pre_eval_gate?.backend_cwd,
          'flow.pre_eval_gate.frontend_checks': existing?.flow?.pre_eval_gate?.frontend_checks,
          'flow.pre_eval_gate.backend_checks': existing?.flow?.pre_eval_gate?.backend_checks,
        };
        // Write template, then re-apply user settings
        fs.writeFileSync(configDest, JSON.stringify(template, null, 2) + '\n');
        // Re-apply preserved user settings
        const merged = JSON.parse(fs.readFileSync(configDest, 'utf8'));
        if (userPreserve.behavior) merged.behavior = userPreserve.behavior;
        if (userPreserve['flow.pre_eval_gate.frontend_cwd']) {
          merged.flow.pre_eval_gate.frontend_cwd = userPreserve['flow.pre_eval_gate.frontend_cwd'];
        }
        if (userPreserve['flow.pre_eval_gate.backend_cwd']) {
          merged.flow.pre_eval_gate.backend_cwd = userPreserve['flow.pre_eval_gate.backend_cwd'];
        }
        if (userPreserve['flow.pre_eval_gate.frontend_checks']) {
          merged.flow.pre_eval_gate.frontend_checks = userPreserve['flow.pre_eval_gate.frontend_checks'];
        }
        if (userPreserve['flow.pre_eval_gate.backend_checks']) {
          merged.flow.pre_eval_gate.backend_checks = userPreserve['flow.pre_eval_gate.backend_checks'];
        }
        fs.writeFileSync(configDest, JSON.stringify(merged, null, 2) + '\n');
        log('config.json updated (user settings preserved)');
      } catch (e) {
        copyFile(configSrc, configDest);
        log('config.json replaced (merge failed)');
      }
    } else {
      copyFile(configSrc, configDest);
    }
  }

  // HARNESS.md — ALWAYS update
  const harnessMdSrc = path.join(PKG_ROOT, 'assets', 'templates', 'HARNESS.md');
  const harnessMdDest = path.join(HARNESS_DIR, 'HARNESS.md');
  if (fs.existsSync(harnessMdSrc)) {
    copyFile(harnessMdSrc, harnessMdDest);
  }

  // Copy memory.md (shared learnings)
  const memorySrc = path.join(PKG_ROOT, 'assets', 'templates', 'memory.md');
  const memoryDest = path.join(HARNESS_DIR, 'memory.md');
  if (fs.existsSync(memorySrc) && (!fileExists(memoryDest) || isForce)) {
    copyFile(memorySrc, memoryDest);
  }

  // Copy CONVENTIONS.md to project root (legacy — root still supported)
  const rootConvSrc = path.join(PKG_ROOT, 'assets', 'templates', 'CONVENTIONS.md');
  const rootConvDest = path.join(PROJECT_ROOT, 'CONVENTIONS.md');
  if (fs.existsSync(rootConvSrc) && (!fileExists(rootConvDest) || isForce)) {
    copyFile(rootConvSrc, rootConvDest);
    log('CONVENTIONS.md created — edit to define top-level project conventions');
  }

  // Create progress.log
  const progressLog = path.join(HARNESS_DIR, 'progress.log');
  if (!fileExists(progressLog) || isForce) {
    const date = new Date().toISOString().split('T')[0];
    fs.writeFileSync(progressLog, `# Harness Progress Log\n# ${date} — Initialized\n`);
  }

  // Create handoff.json placeholder
  const handoff = path.join(HARNESS_DIR, 'handoff.json');
  if (!fileExists(handoff) || isForce) {
    fs.writeFileSync(handoff, '{}');
  }

  log('.harness/ scaffolding complete');
}

// ─────────────────────────────────────────
// 2. Skills → .claude/skills/
// ─────────────────────────────────────────
function installSkills() {
  log('Installing skills to .claude/skills/...');

  const skillsSrc = path.join(PKG_ROOT, 'skills');
  if (!fs.existsSync(skillsSrc)) {
    log('WARNING: skills/ directory not found in package');
    return;
  }

  // harness- 프리픽스 스킬 전체 삭제 후 재복사 — 잔류 방지
  if (fs.existsSync(CLAUDE_SKILLS_DIR)) {
    const existing = fs.readdirSync(CLAUDE_SKILLS_DIR, { withFileTypes: true });
    for (const entry of existing) {
      if (entry.isDirectory() && entry.name.startsWith('harness-')) {
        fs.rmSync(path.join(CLAUDE_SKILLS_DIR, entry.name), { recursive: true, force: true });
      }
    }
    log('  Cleared existing harness-* skills');
  }

  const skills = fs.readdirSync(skillsSrc, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);

  for (const skill of skills) {
    const src = path.join(skillsSrc, skill);
    const dest = path.join(CLAUDE_SKILLS_DIR, `harness-${skill}`);
    copyDir(src, dest);
    log(`  Installed: harness-${skill}`);
  }

  log('Skills installation complete');
}

// ─────────────────────────────────────────
// 3. Scripts
// ─────────────────────────────────────────
function installScripts() {
  log('Installing scripts...');

  const scriptsSrc = path.join(PKG_ROOT, 'scripts');
  const scriptsDest = path.join(PROJECT_ROOT, 'scripts');

  // 전체 삭제 후 재복사 — 버전 간 잔류 파일 방지
  if (fs.existsSync(scriptsDest)) {
    fs.rmSync(scriptsDest, { recursive: true, force: true });
    log('  Cleared existing scripts/');
  }

  if (fs.existsSync(scriptsSrc)) {
    copyDir(scriptsSrc, scriptsDest);

    // chmod +x for all .sh files (recursive)
    function chmodRecursive(dir) {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          chmodRecursive(full);
        } else if (entry.name.endsWith('.sh')) {
          try { fs.chmodSync(full, '755'); } catch (e) {}
        }
      }
    }
    chmodRecursive(scriptsDest);
  }

  log('Scripts installation complete');
}

// ─────────────────────────────────────────
// 3a. Commands → .claude/commands/
// ─────────────────────────────────────────
function installCommands() {
  log('Installing commands to .claude/commands/...');

  const commandsSrc = path.join(PKG_ROOT, 'commands');
  if (!fs.existsSync(commandsSrc)) {
    log('WARNING: commands/ directory not found in package');
    return;
  }

  const commandsDest = path.join(PROJECT_ROOT, '.claude', 'commands');
  ensureDir(commandsDest);

  // Remove existing harness-* commands to prevent stale files
  if (fs.existsSync(commandsDest)) {
    const existing = fs.readdirSync(commandsDest);
    for (const f of existing) {
      if (f.startsWith('harness-')) {
        fs.unlinkSync(path.join(commandsDest, f));
      }
    }
    log('  Cleared existing harness-* commands');
  }

  // Copy all command files
  const files = fs.readdirSync(commandsSrc).filter(f => f.endsWith('.md'));
  for (const file of files) {
    copyFile(path.join(commandsSrc, file), path.join(commandsDest, file));
    log(`  Installed: /${file.replace('.md', '')}`);
  }

  log('Commands installation complete');
}

// ─────────────────────────────────────────
// 3b. SessionStart hook
// ─────────────────────────────────────────
function installSessionHook() {
  log('Installing SessionStart hook...');

  const settingsDir = path.join(PROJECT_ROOT, '.claude');
  const settingsFile = path.join(settingsDir, 'settings.json');

  ensureDir(settingsDir);

  let settings = {};
  if (fileExists(settingsFile)) {
    try {
      settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
    } catch (e) {
      log('WARNING: Could not parse existing .claude/settings.json, creating new');
    }
  }

  // Ensure hooks.SessionStart array exists
  if (!settings.hooks) settings.hooks = {};
  if (!settings.hooks.SessionStart) settings.hooks.SessionStart = [];

  // Migrate any legacy flat entries (created by older walwal-harness versions)
  // into the correct matcher + hooks-array shape that Claude Code expects.
  const hookCmd = 'bash scripts/harness-session-start.sh';
  let migrated = false;
  settings.hooks.SessionStart = settings.hooks.SessionStart
    .map((entry) => {
      if (entry && typeof entry === 'object' && Array.isArray(entry.hooks)) {
        return entry; // already in correct shape
      }
      if (entry && typeof entry === 'object' && entry.type === 'command' && entry.command) {
        migrated = true;
        return { matcher: '', hooks: [{ type: entry.type, command: entry.command }] };
      }
      return entry;
    })
    .filter(Boolean);

  // Check if our hook is already installed (inside any matcher group)
  const alreadyInstalled = settings.hooks.SessionStart.some(
    (entry) =>
      entry &&
      Array.isArray(entry.hooks) &&
      entry.hooks.some(
        (h) => h && h.command && h.command.includes('harness-session-start')
      )
  );

  if (!alreadyInstalled) {
    settings.hooks.SessionStart.push({
      matcher: '',
      hooks: [{ type: 'command', command: hookCmd }]
    });
    fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + '\n');
    log('SessionStart hook installed in .claude/settings.json');
  } else if (migrated) {
    fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + '\n');
    log('SessionStart hook migrated to matcher + hooks-array format');
  } else {
    log('SessionStart hook already installed');
  }
}

// ─────────────────────────────────────────
// 3c. Statusline (persistent status bar)
// ─────────────────────────────────────────
function installStatusline() {
  log('Installing statusline...');

  const settingsDir = path.join(PROJECT_ROOT, '.claude');
  const settingsFile = path.join(settingsDir, 'settings.json');

  ensureDir(settingsDir);

  let settings = {};
  if (fileExists(settingsFile)) {
    try {
      settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
    } catch (e) {
      log('WARNING: Could not parse existing .claude/settings.json, creating new');
    }
  }

  // Check if statusLine is already configured
  if (settings.statusLine && settings.statusLine.command &&
      settings.statusLine.command.includes('harness-statusline')) {
    log('Statusline already installed');
    return;
  }

  settings.statusLine = {
    type: 'command',
    command: 'bash scripts/harness-statusline.sh',
    refreshInterval: 3
  };

  fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + '\n');
  log('Statusline installed — persistent status bar at terminal bottom');
}

// ─────────────────────────────────────────
// 3d. UserPromptSubmit hook (auto dispatcher routing)
// ─────────────────────────────────────────
function installUserPromptSubmitHook() {
  log('Installing UserPromptSubmit hook (auto dispatcher routing)...');

  const settingsDir = path.join(PROJECT_ROOT, '.claude');
  const settingsFile = path.join(settingsDir, 'settings.json');

  ensureDir(settingsDir);

  let settings = {};
  if (fileExists(settingsFile)) {
    try {
      settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
    } catch (e) {
      log('WARNING: Could not parse existing .claude/settings.json, creating new');
    }
  }

  if (!settings.hooks) settings.hooks = {};
  if (!settings.hooks.UserPromptSubmit) settings.hooks.UserPromptSubmit = [];

  const hookCmd = 'bash scripts/harness-user-prompt-submit.sh';

  // Detect existing harness UserPromptSubmit hook (any shape)
  const alreadyInstalled = settings.hooks.UserPromptSubmit.some((entry) => {
    if (!entry || typeof entry !== 'object') return false;
    if (Array.isArray(entry.hooks)) {
      return entry.hooks.some(
        (h) => h && h.command && h.command.includes('harness-user-prompt-submit')
      );
    }
    if (entry.type === 'command' && entry.command) {
      return entry.command.includes('harness-user-prompt-submit');
    }
    return false;
  });

  if (!alreadyInstalled) {
    settings.hooks.UserPromptSubmit.push({
      matcher: '',
      hooks: [{ type: 'command', command: hookCmd }]
    });
    fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + '\n');
    log('UserPromptSubmit hook installed in .claude/settings.json');
    log('  → All prompts will be routed through harness-dispatcher');
    log('  → Opt-out per message: say "harness skip" or "without harness"');
    log('  → Disable globally: set .harness/config.json behavior.auto_route_dispatcher = false');
  } else {
    log('UserPromptSubmit hook already installed');
  }
}

// ─────────────────────────────────────────
// 4. AGENTS.md + CLAUDE.md
// ─────────────────────────────────────────
// ─────────────────────────────────────────
// 3d. Agent Teams env var
// ─────────────────────────────────────────
function installAgentTeamsEnv() {
  const settingsPath = path.join(PROJECT_ROOT, '.claude', 'settings.json');
  let settings = {};
  if (fileExists(settingsPath)) {
    try { settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch (e) {}
  }

  let changed = false;

  // Enable Agent Teams env var
  if (!settings.env) settings.env = {};
  if (settings.env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] !== '1') {
    settings.env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1';
    changed = true;
    log('Agent Teams enabled (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)');
  } else {
    log('Agent Teams already enabled');
  }

  // Add git worktree permission for Team Mode isolation
  if (!settings.permissions) settings.permissions = {};
  if (!settings.permissions.allow) settings.permissions.allow = [];
  const worktreePerms = [
    'Bash(git worktree *)',
    'Bash(git checkout *)',
    'Bash(git merge *)',
    'Bash(git branch *)'
  ];
  for (const perm of worktreePerms) {
    if (!settings.permissions.allow.includes(perm)) {
      settings.permissions.allow.push(perm);
      changed = true;
    }
  }

  if (changed) {
    ensureDir(path.dirname(settingsPath));
    fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');
    log('Git worktree permissions added for Team Mode isolation');
  }
}

function setupAgentsMd() {
  const agentsMd = path.join(PROJECT_ROOT, 'AGENTS.md');
  const claudeMd = path.join(PROJECT_ROOT, 'CLAUDE.md');

  // Run scan if no AGENTS.md
  if (!fileExists(agentsMd) || isForce) {
    log('Running project scan...');
    try {
      execSync(`bash "${path.join(PKG_ROOT, 'scripts', 'scan-project.sh')}" "${PROJECT_ROOT}"`, {
        stdio: 'inherit'
      });
      execSync(`bash "${path.join(PKG_ROOT, 'scripts', 'init-agents-md.sh')}" "${PROJECT_ROOT}"`, {
        stdio: 'inherit'
      });
    } catch (e) {
      log('WARNING: Auto-scan failed. Run manually: bash scripts/scan-project.sh .');
      // Create minimal AGENTS.md
      const templateSrc = path.join(PKG_ROOT, 'assets', 'templates', 'AGENTS.md.template');
      if (fs.existsSync(templateSrc)) {
        let content = fs.readFileSync(templateSrc, 'utf8');
        content = content.replace(/\{\{DATE\}\}/g, new Date().toISOString().split('T')[0]);
        fs.writeFileSync(agentsMd, content);
      }
    }
  }

  // Ensure CLAUDE.md symlink
  if (fileExists(agentsMd)) {
    try {
      const stat = fs.lstatSync(claudeMd);
      if (!stat.isSymbolicLink()) {
        // Backup existing CLAUDE.md
        const backupDir = path.join(HARNESS_DIR, 'archive', 'pre-harness-backup');
        ensureDir(backupDir);
        fs.copyFileSync(claudeMd, path.join(backupDir, `CLAUDE.md.${Date.now()}.bak`));
        fs.unlinkSync(claudeMd);
        fs.symlinkSync('AGENTS.md', claudeMd);
        log('CLAUDE.md backed up and replaced with symlink → AGENTS.md');
      }
    } catch (e) {
      // CLAUDE.md doesn't exist
      try {
        fs.symlinkSync('AGENTS.md', claudeMd);
        log('Created symlink: CLAUDE.md → AGENTS.md');
      } catch (e2) {}
    }
  }
}

// ─────────────────────────────────────────
// 5. Playwright MCP check
// ─────────────────────────────────────────
function checkPlaywrightMcp() {
  const mcpJson = path.join(require('os').homedir(), '.mcp.json');

  if (fileExists(mcpJson)) {
    try {
      const config = JSON.parse(fs.readFileSync(mcpJson, 'utf8'));
      if (config.mcpServers && config.mcpServers.playwright) {
        log('Playwright MCP: already configured');
        return;
      }
    } catch (e) {}
  }

  log('');
  log('NOTE: Playwright MCP is not configured.');
  log('Evaluator agents require Playwright MCP for browser testing.');
  log('Add to ~/.mcp.json:');
  log('');
  log('  {');
  log('    "mcpServers": {');
  log('      "playwright": {');
  log('        "command": "npx",');
  log('        "args": ["-y", "@playwright/mcp@latest", "--headless", "--caps", "vision"]');
  log('      }');
  log('    }');
  log('  }');
  log('');
}

// ─────────────────────────────────────────
// 6. Recommended skills check
// ─────────────────────────────────────────
function checkRecommendedSkills() {
  const configPath = path.join(HARNESS_DIR, 'config.json');
  if (!fileExists(configPath)) return;

  let config;
  try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (e) { return; }

  const skills = config.recommended_skills;
  if (!skills) return;

  const missing = [];
  const found = [];

  for (const [name, info] of Object.entries(skills)) {
    if (name === 'comment') continue;
    const checkPath = path.join(PROJECT_ROOT, info.check_path);
    if (fileExists(checkPath)) {
      found.push(name);
    } else {
      missing.push({ name, ...info });
    }
  }

  if (found.length > 0) {
    log(`Recommended skills installed: ${found.join(', ')}`);
  }

  if (missing.length > 0) {
    console.log('');
    log('╔═══════════════════════════════════════════════════════════╗');
    log('║  Recommended skills (not installed)                      ║');
    log('╠═══════════════════════════════════════════════════════════╣');
    for (const skill of missing) {
      const agents = skill.used_by.join(', ');
      log(`║  ${skill.name}`);
      log(`║    ${skill.description}`);
      log(`║    Used by: ${agents}`);
      log(`║    Install: ${skill.install}`);
      log('║');
    }
    log('║  These skills are optional but improve output quality.   ║');
    log('║  Harness reference files provide baseline guidance       ║');
    log('║  even without these skills installed.                    ║');
    log('╚═══════════════════════════════════════════════════════════╝');
  } else if (found.length > 0) {
    log('All recommended skills are installed!');
  }
}

// ─────────────────────────────────────────
// Help
// ─────────────────────────────────────────
function showHelp() {
  const pkg = require(path.join(PKG_ROOT, 'package.json'));
  console.log(`
╔══════════════════════════════════════╗
║     walwal-harness v${pkg.version.padEnd(16)}║
║     AI Agent Harness Engineering     ║
╚══════════════════════════════════════╝

Usage:
  npx walwal-harness              Initialize project for harness engineering
  npx walwal-harness --force      Re-initialize (overwrites existing files)
  npx walwal-harness team         Launch Team Mode (tmux studio + auto teams)
  npx walwal-harness team --kill  Kill Team Mode tmux session
  npx walwal-harness --help       Show this help

Modes (use inside claude/codex session):
  /harness-solo       Solo mode — prompting-based sequential pipeline
  /harness-team       Team mode — auto parallel Gen-Eval loop (3 teams)
  /harness-stop       Stop Team mode (preserves queue state)

What it does:
  1. Scaffolds .harness/ directory (actions, archive, gotchas, config)
  2. Installs skills to .claude/skills/ (dispatcher, planner, generators, evaluators)
  3. Installs commands to .claude/commands/ (solo, team, stop)
  4. Copies helper scripts to scripts/
  5. Registers SessionStart + UserPromptSubmit hooks
  6. Installs statusline (persistent 1-line status bar)
  7. Creates AGENTS.md + CLAUDE.md symlink

After init:
  1. Restart Claude Code session (/exit → re-enter directory)
  2. Say "하네스 엔지니어링 시작" or /harness-dispatcher
  3. After Planner completes: /harness-team (team) or continue prompting (solo)
`);
}

// ─────────────────────────────────────────
// Main
// ─────────────────────────────────────────
function runTeamStudio() {
  const killMode = args.includes('--kill');
  const scriptsDir = path.join(PKG_ROOT, 'scripts');
  const tmuxScript = path.join(scriptsDir, 'harness-tmux.sh');

  if (!fs.existsSync(tmuxScript)) {
    log('ERROR: harness-tmux.sh not found.');
    process.exit(1);
  }

  try {
    execSync('which tmux', { stdio: 'ignore' });
  } catch {
    log('ERROR: tmux is required. Install with: brew install tmux');
    process.exit(1);
  }

  if (killMode) {
    const cmd = `bash "${tmuxScript}" --kill`;
    execSync(cmd, { stdio: 'inherit' });
    return;
  }

  // Enable Agent Teams in project settings
  installAgentTeamsEnv();

  const cmd = `bash "${tmuxScript}" "${PROJECT_ROOT}" --team`;
  log('Launching Team Mode Studio...');
  execSync(cmd, { stdio: 'inherit' });
}

function main() {
  if (isHelp) {
    showHelp();
    return;
  }

  if (subcommand === 'team') {
    runTeamStudio();
    return;
  }

  // Legacy subcommands — redirect to new equivalents
  if (subcommand === 'studio' || subcommand === 'studio-v4' || subcommand === 'v4') {
    log('NOTE: "studio" and "v4" subcommands are replaced by "team".');
    runTeamStudio();
    return;
  }

  const pkg = require(path.join(PKG_ROOT, 'package.json'));
  console.log('');
  console.log('╔══════════════════════════════════════╗');
  console.log(`║     walwal-harness v${pkg.version.padEnd(16)}║`);
  console.log('║     AI Agent Harness Engineering     ║');
  console.log('╚══════════════════════════════════════╝');
  console.log('');

  log(`Project root: ${PROJECT_ROOT}`);
  console.log('');

  scaffoldHarness();
  installSkills();
  installScripts();
  installCommands();
  installSessionHook();
  installStatusline();
  installUserPromptSubmitHook();
  installAgentTeamsEnv();
  setupAgentsMd();
  checkPlaywrightMcp();
  checkRecommendedSkills();

  console.log('');
  log('═══ Initialization Complete ═══');
  log('');

  if (isAuto) {
    log('╔═══════════════════════════════════════════════════════════╗');
    log('║  Restart Claude Code for skills & commands to activate!  ║');
    log('║                                                          ║');
    log('║  Then say: "하네스 엔지니어링 시작"                        ║');
    log('║  Or invoke: /harness-dispatcher                          ║');
    log('║                                                          ║');
    log('║  기본은 Solo 모드 (순차 진행) — 입력 불필요.              ║');
    log('║  병렬 3팀 실행을 원하면 파이프라인 확정 후 /harness-team  ║');
    log('╚═══════════════════════════════════════════════════════════╝');
  } else {
    log('Next steps:');
    log('  1. Restart Claude Code session (/exit → re-enter directory)');
    log('  2. Say "하네스 엔지니어링 시작" or /harness-dispatcher');
    log('  3. Solo 모드는 자동. Team 모드 원할 때만 파이프라인 확정 후 /harness-team');
  }
  console.log('');
}

main();
