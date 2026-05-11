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
const CLAUDE_COMMANDS_DIR = path.join(PROJECT_ROOT, '.claude', 'commands');
const CODEX_SKILLS_DIR = path.join(PROJECT_ROOT, '.codex', 'skills');
const CODEX_COMMANDS_DIR = path.join(PROJECT_ROOT, '.codex', 'commands');

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

const V7_REMOVED_CONVENTION_FILES = [
  'conductor.md',
  'coo-developer.md',
  'dispatcher.md',
  'documentationer.md',
  'evaluator-architecture.md',
  'evaluator-code-quality.md',
  'evaluator-functional.md',
  'evaluator-security.md',
  'evaluator-visual.md',
  'generator-backend.md',
  'generator-designer.md',
  'generator-devops.md',
  'generator-frontend.md',
  'meeting-manager.md',
  'planner.md',
  'service-ops.md',
];

const V7_REMOVED_GOTCHA_FILES = [
  ...V7_REMOVED_CONVENTION_FILES,
  'generator-backend-laravel.md',
];

function removeLegacyV7Files(dir, files) {
  for (const file of files) {
    const target = path.join(dir, file);
    if (fs.existsSync(target)) {
      fs.rmSync(target, { force: true });
    }
  }
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
    if (/\b(ceo|dispatcher|owner|goal|hot-?fix|mission)\b/.test(b)) return 'ceo';
    if (/\b(coo|planning|research|hypothesis|backtest|reference)\b/.test(b)) return 'coo';
    if (/\b(cdo|design|brand|ui|ux|mock|visual)\b/.test(b)) return 'cdo';
    if (/\b(cto|architecture|backend|frontend|api|platform|account|devops|implementation)\b/.test(b)) return 'cto';
    if (/\b(cqo|quality|regression|e2e|test|archive|memory|gotcha)\b/.test(b)) return 'cqo';
    if (/\b(ops|operation|service|log|incident|deploy|launch)\b/.test(b)) return 'ops';
    if (/\b(hiring|hire|recruit|hr-resource|worker)\b/.test(b)) return 'hiring';
    if (/\b(resource-manager|resource manager|alias|keyword|wording)\b/.test(b)) return 'resource-manager';
    if (/\b(brick-office|dashboard)\b/.test(b)) return 'brick-office';
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
        extractedGotcha.counter += 1;
        const id = `G-${String(extractedGotcha.counter).padStart(3, '0')}`;
        const target = path.join(HARNESS_DIR, 'gotchas', `${scope}.md`);
        appendEntry(target, id, 'gotcha', sec.title, body, sourceRef);
        extractedGotcha.byAgent[scope] = (extractedGotcha.byAgent[scope] || 0) + 1;
        report.push(`[${id}] "${sec.title}" → gotchas/${scope}.md  (from ${sourceRef})`);
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
  ensureDir(path.join(HARNESS_DIR, 'documents'));
  ensureDir(path.join(HARNESS_DIR, 'logs'));
  ensureDir(path.join(HARNESS_DIR, 'memories'));
  ensureDir(path.join(HARNESS_DIR, 'shared'));

  removeLegacyV7Files(path.join(HARNESS_DIR, 'conventions'), V7_REMOVED_CONVENTION_FILES);
  removeLegacyV7Files(path.join(HARNESS_DIR, 'gotchas'), V7_REMOVED_GOTCHA_FILES);

  const hrResourceSrc = path.join(PKG_ROOT, 'HR-Resource');
  const hrResourceDest = path.join(HARNESS_DIR, 'shared', 'HR-Resource');
  if (fs.existsSync(hrResourceSrc) && (!fs.existsSync(hrResourceDest) || isForce)) {
    copyDir(hrResourceSrc, hrResourceDest);
    log('HR-Resource copied to .harness/shared/HR-Resource');
  }

  const rosterPath = path.join(HARNESS_DIR, 'shared', 'hr-roster.json');
  if (!fileExists(rosterPath) || isForce) {
    fs.writeFileSync(rosterPath, JSON.stringify({ hired: [] }, null, 2) + '\n');
  }

  const resourceIndexPath = path.join(HARNESS_DIR, 'shared', 'resource-index.json');
  if (!fileExists(resourceIndexPath) || isForce) {
    fs.writeFileSync(resourceIndexPath, JSON.stringify({ aliases: {}, keywords: {} }, null, 2) + '\n');
  }

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
    const CONV_ENTRY = /^### \[C-[A-Z0-9_-]+\]/m;
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
        progress.mode = 'company';
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
  log('Installing skills to .claude/skills/ and .codex/skills/...');

  const hrSrc = path.join(PKG_ROOT, 'HR-Resource');
  const destinations = [CLAUDE_SKILLS_DIR, CODEX_SKILLS_DIR];

  for (const destRoot of destinations) {
    ensureDir(destRoot);
    const existing = fs.readdirSync(destRoot, { withFileTypes: true });
    for (const entry of existing) {
      if (entry.isDirectory() && entry.name.startsWith('harness-')) {
        fs.rmSync(path.join(destRoot, entry.name), { recursive: true, force: true });
      }
    }
  }
  log('  Cleared existing harness-* skills');

  const installSkillDir = (src, destName) => {
    for (const destRoot of destinations) {
      copyDir(src, path.join(destRoot, destName));
    }
    log(`  Installed: ${destName}`);
  };

  const coreHrSkills = ['ceo', 'coo', 'cdo', 'cto', 'cqo', 'ops', 'hiring', 'resource-manager', 'brick-office'];
  if (fs.existsSync(hrSrc)) {
    for (const skill of coreHrSkills) {
      const src = path.join(hrSrc, skill);
      if (fs.existsSync(src)) installSkillDir(src, `harness-${skill}`);
    }
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
  log('Installing commands to .claude/commands/ and .codex/commands/...');

  const commandsSrc = path.join(PKG_ROOT, 'commands');
  if (!fs.existsSync(commandsSrc)) {
    log('WARNING: commands/ directory not found in package');
    return;
  }

  const commandDests = [CLAUDE_COMMANDS_DIR, CODEX_COMMANDS_DIR];
  commandDests.forEach(ensureDir);

  // Remove existing harness-* commands to prevent stale files
  for (const commandsDest of commandDests) {
    const existing = fs.readdirSync(commandsDest);
    for (const f of existing) {
      if (f.startsWith('harness-') || ['goal.md', 'hot-fix.md', 'brick-office.md', 'hiring.md', 'resource-manager.md', 'ceo.md', 'coo.md', 'cdo.md', 'cto.md', 'cqo.md', 'ops.md'].includes(f)) {
        fs.unlinkSync(path.join(commandsDest, f));
      }
    }
  }
  log('  Cleared existing harness commands');

  // Copy all command files
  const files = fs.readdirSync(commandsSrc).filter(f => f.endsWith('.md'));
  for (const file of files) {
    for (const commandsDest of commandDests) {
      copyFile(path.join(commandsSrc, file), path.join(commandsDest, file));
    }
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
// 3e. Stop hook (auto-chain conductor tick)
// ─────────────────────────────────────────
function installStopHook() {
  log('Installing Stop hook (auto-chain conductor tick)...');

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
  if (!settings.hooks.Stop) settings.hooks.Stop = [];

  const hookCmd = 'bash scripts/harness-stop.sh';

  const alreadyInstalled = settings.hooks.Stop.some((entry) => {
    if (!entry || typeof entry !== 'object') return false;
    if (Array.isArray(entry.hooks)) {
      return entry.hooks.some(
        (h) => h && h.command && h.command.includes('harness-stop')
      );
    }
    if (entry.type === 'command' && entry.command) {
      return entry.command.includes('harness-stop');
    }
    return false;
  });

  if (!alreadyInstalled) {
    settings.hooks.Stop.push({
      matcher: '',
      hooks: [{ type: 'command', command: hookCmd }]
    });
    fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + '\n');
    log('Stop hook installed in .claude/settings.json');
    log('  → Conductor 가 running 인 동안 turn 종료 시 자동으로 다음 tick 으로 연쇄');
    log('  → 비활성: .harness/config.json behavior.auto_chain_on_stop = false');
    log('  → 상한: behavior.auto_chain_max_per_sprint (기본 200)');
  } else {
    log('Stop hook already installed');
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

  // Add git worktree permission for parallel worker isolation
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
    log('Git worktree permissions added for parallel worker isolation');
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
  npx walwal-harness init                  Initialize project for harness engineering
  npx walwal-harness init --force          Re-initialize (overwrites existing harness files)
  npx walwal-harness migrate               Apply migration (always-on company mode)
  npx walwal-harness migrate --dry-run     Preview migration changes without applying
  npx walwal-harness verify                Verify install integrity
  npx walwal-harness --help                Show this help

Runtime (always-on company mode):
  - Stop 훅이 매 turn 종료 시 다음 부서로 자동 연쇄.
  - 1시간 안전망 wake (선택): bash scripts/harness-wake-install.sh install .
  - 3D 대시보드 (선택): bash scripts/harness-dashboard-up.sh
  - Owner 입력은 GOAL 모호성, escalation, 결과 보고에만 필요합니다.

What it does:
  1. Scaffolds project-local .harness/ runtime state
  2. Installs commands to .claude/commands/ and .codex/commands/
  3. Installs CXX and harness skills to .claude/skills/ and .codex/skills/
  4. Copies HR-Resource to .harness/shared/HR-Resource for hiring
  4. Registers SessionStart + UserPromptSubmit + Stop hooks
  5. Installs statusline (persistent 1-line status bar)
  6. Creates AGENTS.md + CLAUDE.md symlink when needed

After init:
  1. Restart Claude/Codex session if command discovery needs refresh.
  2. Use /goal or /hot-fix.
  3. Internal agents must call hired agents/skills, not slash commands.
`);
}

// ─────────────────────────────────────────
// Migration — legacy mode fields → always-on company mode
// ─────────────────────────────────────────
const TARGET_PROGRESS_VERSION = 4;

// System memory entries that must exist in every install. ID prefix convention:
//   M-NEXUS-*  : Foundational NEXUS doctrine rules
//   M-SYS-*    : Cross-agent system-level rules
// User-added [M-NNN] entries are NEVER touched.
const SYSTEM_MEMORY_ENTRY_PATTERN = /^### \[M-(NEXUS|SYS)-[A-Z0-9_-]+\]/m;

function detectMigrationNeeded() {
  const progressPath = path.join(HARNESS_DIR, 'progress.json');
  const configPath = path.join(HARNESS_DIR, 'config.json');
  const memoryPath = path.join(HARNESS_DIR, 'memory.md');
  const memoryTplPath = path.join(PKG_ROOT, 'assets', 'templates', 'memory.md');
  const flags = {
    progressV3toV4: false,
    configMissingCompanyMode: false,
    memoryMissingSystemEntries: [],
    gotchaMissingEntries: {},   // { "<filename>": [G-IDs...] }
    conventionMissingEntries: {}, // { "<filename>": [C-IDs...] }
    bundleVersionStale: null,    // { current, installed }
  };

  // Gotcha entry-level diff: for each bundled gotcha file, compare entry IDs.
  // 사용자가 직접 추가한 [G-NNN] 은 절대 건드리지 않으며, 패키지에서 새로
  // 도입된 시스템 entry 만 append 대상.
  const gotchasSrc = path.join(PKG_ROOT, 'gotchas');
  const gotchasDest = path.join(HARNESS_DIR, 'gotchas');
  if (fs.existsSync(gotchasSrc) && fs.existsSync(gotchasDest)) {
    const files = fs.readdirSync(gotchasSrc).filter((f) => f.endsWith('.md') && f !== 'README.md');
    for (const file of files) {
      const srcPath = path.join(gotchasSrc, file);
      const destPath = path.join(gotchasDest, file);
      if (!fs.existsSync(destPath)) continue;  // installSkills/init 이 처리
      try {
        const srcIds = extractGotchaEntryIds(fs.readFileSync(srcPath, 'utf8'));
        const dstIds = new Set(extractGotchaEntryIds(fs.readFileSync(destPath, 'utf8')));
        const missing = srcIds.filter((id) => !dstIds.has(id));
        if (missing.length) flags.gotchaMissingEntries[file] = missing;
      } catch {}
    }
  }

  // Convention entry-level diff: preserve user [C-NNN] entries, append only
  // bundled system entries such as [C-SYS-*].
  const conventionsSrc = path.join(PKG_ROOT, 'conventions');
  const conventionsDest = path.join(HARNESS_DIR, 'conventions');
  if (fs.existsSync(conventionsSrc) && fs.existsSync(conventionsDest)) {
    const files = fs.readdirSync(conventionsSrc).filter((f) => f.endsWith('.md') && f !== 'README.md');
    for (const file of files) {
      const srcPath = path.join(conventionsSrc, file);
      const destPath = path.join(conventionsDest, file);
      if (!fs.existsSync(destPath)) continue;
      try {
        const srcIds = extractConventionEntryIds(fs.readFileSync(srcPath, 'utf8'));
        const dstIds = new Set(extractConventionEntryIds(fs.readFileSync(destPath, 'utf8')));
        const missing = srcIds.filter((id) => !dstIds.has(id));
        if (missing.length) flags.conventionMissingEntries[file] = missing;
      } catch {}
    }
  }

  // Bundle version stamp: detects fresh package vs. last-applied bundle.
  // Even if the 3 schema flags pass, a newer bundle may have introduced new
  // gotcha/SKILL/template content the user hasn't seen yet.
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(PKG_ROOT, 'package.json'), 'utf8'));
    const stampPath = path.join(HARNESS_DIR, '.bundle-version');
    const installed = fs.existsSync(stampPath) ? fs.readFileSync(stampPath, 'utf8').trim() : null;
    if (installed !== pkg.version) {
      flags.bundleVersionStale = { current: pkg.version, installed };
    }
  } catch {}
  if (fs.existsSync(progressPath)) {
    try {
      const p = JSON.parse(fs.readFileSync(progressPath, 'utf8'));
      if ((p.version ?? 0) < TARGET_PROGRESS_VERSION) flags.progressV3toV4 = true;
    } catch {}
  }
  if (fs.existsSync(configPath)) {
    try {
      const c = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      if (!c.company_mode || c.mode_selection) flags.configMissingCompanyMode = true;
    } catch {}
  }
  if (fs.existsSync(memoryPath) && fs.existsSync(memoryTplPath)) {
    try {
      const userMem = fs.readFileSync(memoryPath, 'utf8');
      const tplMem = fs.readFileSync(memoryTplPath, 'utf8');
      const tplEntryIds = extractEntryIds(tplMem).filter((id) => /^M-(NEXUS|SYS)-/.test(id));
      const userEntryIds = new Set(extractEntryIds(userMem));
      flags.memoryMissingSystemEntries = tplEntryIds.filter((id) => !userEntryIds.has(id));
    } catch {}
  }
  return flags;
}

// Returns the list of memory entry IDs found in the markdown body, e.g. ["M-001", "M-NEXUS-P3"].
function extractEntryIds(md) {
  const re = /^### \[(M-[A-Z0-9_-]+)\]/gm;
  const ids = [];
  let m;
  while ((m = re.exec(md)) !== null) ids.push(m[1]);
  return ids;
}

// Extracts a single entry block (heading + body until next ### or EOF) from the template.
function extractEntryBlock(md, id) {
  const escId = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(^### \\[${escId}\\][\\s\\S]*?)(?=^### \\[|$(?![\\s\\S]))`, 'm');
  const m = md.match(re);
  return m ? m[1].trimEnd() : null;
}

// Returns gotcha entry IDs ("[G-001]", "[G-NEXUS-P3]" etc.) found in a markdown body.
// Supports both `### [G-NNN]` and `## [G-NNN] ...` heading levels.
function extractGotchaEntryIds(md) {
  const re = /^#{2,3}\s+\[(G-[A-Z0-9_-]+)\]/gm;
  const ids = [];
  let m;
  while ((m = re.exec(md)) !== null) ids.push(m[1]);
  return ids;
}

// Extracts a single gotcha entry block from a markdown body.
function extractGotchaEntryBlock(md, id) {
  const escId = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  // JS lacks \Z; emulate end-of-string via (?![\s\S]) negative lookahead.
  const re = new RegExp(
    `(^#{2,3}\\s+\\[${escId}\\][\\s\\S]*?)(?=^#{2,3}\\s+\\[G-|$(?![\\s\\S]))`,
    'm',
  );
  const m = md.match(re);
  return m ? m[1].trimEnd() : null;
}

// Returns convention entry IDs ("[C-001]", "[C-SYS-*]" etc.) found in markdown.
function extractConventionEntryIds(md) {
  const re = /^#{2,3}\s+\[(C-[A-Z0-9_-]+)\]/gm;
  const ids = [];
  let m;
  while ((m = re.exec(md)) !== null) ids.push(m[1]);
  return ids;
}

function extractConventionEntryBlock(md, id) {
  const escId = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(
    `(^#{2,3}\\s+\\[${escId}\\][\\s\\S]*?)(?=^#{2,3}\\s+\\[C-|$(?![\\s\\S]))`,
    'm',
  );
  const m = md.match(re);
  return m ? m[1].trimEnd() : null;
}

function showMigrationProposal(flags) {
  console.log('');
  console.log('╔══════════════════════════════════════════════════════════╗');
  console.log('║  walwal-harness v6 — 자동 마이그레이션 사용 가능         ║');
  console.log('╚══════════════════════════════════════════════════════════╝');
  if (flags.progressV3toV4) {
    console.log('  • progress.json: legacy mode → "company"');
    console.log('    legacy mode 값은 보존하지 않고 회사모드로 정규화됩니다.');
  }
  if (flags.configMissingCompanyMode) {
    console.log('  • config.json: company_mode 섹션 동기화 가능');
    console.log('    사용자 모드 선택 없이 회사모드 병렬 실행으로 고정합니다.');
  }
  if (flags.memoryMissingSystemEntries && flags.memoryMissingSystemEntries.length) {
    console.log('  • memory.md: 시스템 entry 누락 — append 가능');
    console.log('    [' + flags.memoryMissingSystemEntries.join(', ') + ']');
    console.log('    사용자 [M-NNN] entry 는 보존, 시스템 entry 만 끝에 추가.');
  }
  const gotchaSummary = Object.entries(flags.gotchaMissingEntries || {});
  if (gotchaSummary.length) {
    console.log('  • gotchas/: 시스템 entry 누락 — entry-level append 가능 (사용자 [G-NNN] 보존)');
    for (const [file, ids] of gotchaSummary) {
      console.log(`    ${file}: [${ids.join(', ')}]`);
    }
  }
  const conventionSummary = Object.entries(flags.conventionMissingEntries || {});
  if (conventionSummary.length) {
    console.log('  • conventions/: 시스템 entry 누락 — entry-level append 가능 (사용자 [C-NNN] 보존)');
    for (const [file, ids] of conventionSummary) {
      console.log(`    ${file}: [${ids.join(', ')}]`);
    }
  }
  if (flags.bundleVersionStale) {
    const { current, installed } = flags.bundleVersionStale;
    console.log(`  • bundle: ${installed ?? '(없음)'} → ${current} 스탬프 갱신 필요`);
  }
  console.log('');
  console.log('  적용:  npx walwal-harness migrate');
  console.log('  미리보기:  npx walwal-harness migrate --dry-run');
  console.log('');
  console.log('  ※ 자동 강제 X — 사용자가 명령을 실행할 때만 변경됩니다.');
  console.log('  ※ 변경 전 .harness/archive/migration-<ts>/ 에 자동 백업.');
  console.log('');
}

function runMigrate(opts = {}) {
  const dryRun = opts.dryRun || false;
  const flags = detectMigrationNeeded();
  const gotchaMissingTotal = Object.values(flags.gotchaMissingEntries || {}).reduce((n, a) => n + a.length, 0);
  if (
    !flags.progressV3toV4 &&
    !flags.configMissingCompanyMode &&
    (!flags.memoryMissingSystemEntries || flags.memoryMissingSystemEntries.length === 0) &&
    gotchaMissingTotal === 0 &&
    !flags.bundleVersionStale
  ) {
    console.log('');
    let pkgVer = 'unknown';
    try { pkgVer = JSON.parse(fs.readFileSync(path.join(PKG_ROOT, 'package.json'), 'utf8')).version; } catch {}
    log(`이미 최신 — bundle v${pkgVer} 일치, progress v${TARGET_PROGRESS_VERSION}, config.company_mode, memory 시스템 entry, gotcha entry 모두 sync.`);
    return;
  }

  console.log('');
  log(dryRun ? '=== DRY RUN — 실제 변경 없음 ===' : '=== Migration 적용 ===');

  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const backupDir = path.join(HARNESS_DIR, 'archive', `migration-${ts}`);
  if (!dryRun) ensureDir(backupDir);

  // 1. progress.json
  const progressPath = path.join(HARNESS_DIR, 'progress.json');
  if (flags.progressV3toV4 && fs.existsSync(progressPath)) {
    const original = fs.readFileSync(progressPath, 'utf8');
    const p = JSON.parse(original);
    const oldMode = p.mode ?? 'company';
    const newP = {
      ...p,
      version: TARGET_PROGRESS_VERSION,
      mode: 'company',
      mode_decision: {
        owner: 'conductor',
        decided_at: null,
        rationale: `migration — legacy mode="${oldMode}" normalized to company`,
        policy: 'always_company_parallel',
        user_override: null,
      },
    };
    log(`  progress.json: version 3 → ${TARGET_PROGRESS_VERSION}, mode "${oldMode}" → "company"`);
    if (!dryRun) {
      fs.writeFileSync(path.join(backupDir, 'progress.json'), original);
      fs.writeFileSync(progressPath, JSON.stringify(newP, null, 2) + '\n');
    }
  }

  // 2. config.json — inject company_mode from template if missing
  const configPath = path.join(HARNESS_DIR, 'config.json');
  const tplPath = path.join(PKG_ROOT, 'assets', 'templates', 'config.json');
  if (flags.configMissingCompanyMode && fs.existsSync(configPath) && fs.existsSync(tplPath)) {
    const original = fs.readFileSync(configPath, 'utf8');
    const c = JSON.parse(original);
    const tpl = JSON.parse(fs.readFileSync(tplPath, 'utf8'));
    if (tpl.company_mode) {
      c.company_mode = tpl.company_mode;
      delete c.mode_selection;
      log('  config.json: company_mode 섹션 주입 (always-on company parallel)');
      if (!dryRun) {
        fs.writeFileSync(path.join(backupDir, 'config.json'), original);
        fs.writeFileSync(configPath, JSON.stringify(c, null, 2) + '\n');
      }
    }
  }

  // 3. memory.md — append missing system entries (M-NEXUS-*, M-SYS-*) only.
  //    User-added [M-NNN] entries are NEVER touched.
  const memoryPath = path.join(HARNESS_DIR, 'memory.md');
  const memoryTplPath = path.join(PKG_ROOT, 'assets', 'templates', 'memory.md');
  const missingMemEntries = flags.memoryMissingSystemEntries || [];
  if (missingMemEntries.length && fs.existsSync(memoryPath) && fs.existsSync(memoryTplPath)) {
    const original = fs.readFileSync(memoryPath, 'utf8');
    const tpl = fs.readFileSync(memoryTplPath, 'utf8');
    const blocks = [];
    for (const id of missingMemEntries) {
      const block = extractEntryBlock(tpl, id);
      if (block) blocks.push(block);
    }
    if (blocks.length) {
      log(`  memory.md: 시스템 entry ${blocks.length}개 append (${missingMemEntries.join(', ')})`);
      if (!dryRun) {
        fs.writeFileSync(path.join(backupDir, 'memory.md'), original);
        const sep = original.endsWith('\n') ? '\n' : '\n\n';
        fs.writeFileSync(memoryPath, original + sep + blocks.join('\n\n') + '\n');
      }
    }
  }

  // 4. gotcha entry merge — for each bundled gotcha file, append missing
  //    [G-NNN] entries while preserving everything the user already has.
  const gotchaMissing = flags.gotchaMissingEntries || {};
  for (const [file, missingIds] of Object.entries(gotchaMissing)) {
    if (!missingIds.length) continue;
    const srcPath = path.join(PKG_ROOT, 'gotchas', file);
    const destPath = path.join(HARNESS_DIR, 'gotchas', file);
    if (!fs.existsSync(srcPath) || !fs.existsSync(destPath)) continue;
    const original = fs.readFileSync(destPath, 'utf8');
    const tpl = fs.readFileSync(srcPath, 'utf8');
    const blocks = [];
    for (const id of missingIds) {
      const block = extractGotchaEntryBlock(tpl, id);
      if (block) blocks.push(block);
    }
    if (!blocks.length) continue;
    log(`  gotchas/${file}: 시스템 entry ${blocks.length}개 append (${missingIds.join(', ')})`);
    if (!dryRun) {
      fs.writeFileSync(path.join(backupDir, `gotchas-${file}`), original);
      const sep = original.endsWith('\n') ? '\n' : '\n\n';
      fs.writeFileSync(destPath, original + sep + blocks.join('\n\n') + '\n');
    }
  }

  // 4b. convention entry merge — append bundled system [C-*] entries while
  //     preserving user-authored [C-NNN] history.
  const conventionMissing = flags.conventionMissingEntries || {};
  for (const [file, missingIds] of Object.entries(conventionMissing)) {
    if (!missingIds.length) continue;
    const srcPath = path.join(PKG_ROOT, 'conventions', file);
    const destPath = path.join(HARNESS_DIR, 'conventions', file);
    if (!fs.existsSync(srcPath) || !fs.existsSync(destPath)) continue;
    const original = fs.readFileSync(destPath, 'utf8');
    const tpl = fs.readFileSync(srcPath, 'utf8');
    const blocks = [];
    for (const id of missingIds) {
      const block = extractConventionEntryBlock(tpl, id);
      if (block) blocks.push(block);
    }
    if (!blocks.length) continue;
    log(`  conventions/${file}: 시스템 entry ${blocks.length}개 append (${missingIds.join(', ')})`);
    if (!dryRun) {
      fs.writeFileSync(path.join(backupDir, `conventions-${file}`), original);
      const sep = original.endsWith('\n') ? '\n' : '\n\n';
      fs.writeFileSync(destPath, original + sep + blocks.join('\n\n') + '\n');
    }
  }

  // 5. Bundle version stamp — record which package version was last applied.
  if (flags.bundleVersionStale) {
    const { current, installed } = flags.bundleVersionStale;
    log(`  .bundle-version: ${installed ?? '(none)'} → ${current}`);
    if (!dryRun) {
      fs.writeFileSync(path.join(HARNESS_DIR, '.bundle-version'), current + '\n');
    }
  }

  console.log('');
  if (dryRun) {
    log('Dry-run 완료 — 실제 변경 적용하려면 `npx walwal-harness migrate` 실행');
  } else {
    log(`Migration 완료. 백업: ${backupDir}`);
    log('Conductor 가 다음 sprint 시작 시 자동으로 모드 결정합니다.');
    log('회사모드는 기본값이며 사용자 override 는 사용하지 않습니다.');
  }
  console.log('');
}

// ─────────────────────────────────────────
// Verify — 14 SKILL invariants + spawn whitelist + progress schema
// ─────────────────────────────────────────
function runVerify() {
  const expectedSkills = [
    'dispatcher', 'conductor', 'meeting-manager', 'planner',
    'cto', 'cqo', 'service-ops',
    'generator-backend', 'generator-frontend', 'generator-designer', 'generator-devops',
    'evaluator-code-quality', 'evaluator-functional', 'evaluator-visual',
    'evaluator-architecture', 'evaluator-security',
    'coo-developer', 'documentationer',
    'brainstorming',
  ];
  const requiredFrontmatter = ['name', 'description'];

  console.log('');
  log('=== Verify: skill invariants + spawn whitelist + progress schema ===');
  let pass = 0;
  let fail = 0;
  const issues = [];

  // 1) skill files
  for (const s of expectedSkills) {
    const local = path.join(CLAUDE_SKILLS_DIR, `harness-${s}`, 'SKILL.md');
    const exists = fs.existsSync(local);
    if (!exists) {
      issues.push(`  ✗ skills/harness-${s}/SKILL.md MISSING`);
      fail++;
      continue;
    }
    const body = fs.readFileSync(local, 'utf8');
    const fmMatch = body.match(/^---\n([\s\S]*?)\n---/);
    if (!fmMatch) {
      issues.push(`  ✗ harness-${s}: frontmatter 누락`);
      fail++;
      continue;
    }
    const missing = requiredFrontmatter.filter((k) => !new RegExp(`^${k}:`, 'm').test(fmMatch[1]));
    if (missing.length) {
      issues.push(`  ✗ harness-${s}: frontmatter [${missing.join(',')}] 누락`);
      fail++;
      continue;
    }
    pass++;
  }
  log(`  skills: ${pass}/${expectedSkills.length} OK`);

  // 2) progress.json schema (v6 = version 4 + mode_decision)
  const progressPath = path.join(HARNESS_DIR, 'progress.json');
  if (fs.existsSync(progressPath)) {
    try {
      const p = JSON.parse(fs.readFileSync(progressPath, 'utf8'));
      const schemaIssues = [];
      if ((p.version ?? 0) < 4) schemaIssues.push(`version=${p.version} (<4)`);
      if (!p.mode_decision) schemaIssues.push('mode_decision 누락');
      if (!p.dispatch) schemaIssues.push('dispatch 누락');
      if (schemaIssues.length) {
        issues.push(`  ✗ progress.json schema: ${schemaIssues.join(', ')} → npx walwal-harness migrate`);
        fail++;
      } else {
        pass++;
        log(`  progress.json: schema v${p.version} OK`);
      }
    } catch (e) {
      issues.push(`  ✗ progress.json parse: ${e.message}`);
      fail++;
    }
  }

  // 3) config.json company_mode
  const configPath = path.join(HARNESS_DIR, 'config.json');
  if (fs.existsSync(configPath)) {
    try {
      const c = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      if (!c.company_mode) {
        issues.push('  ✗ config.json: company_mode 누락 → npx walwal-harness migrate');
        fail++;
      } else {
        pass++;
        log(`  config.json: company_mode.owner=${c.company_mode.owner} OK`);
      }
    } catch {}
  }

  // 4) memory.md system entries
  const memoryPath = path.join(HARNESS_DIR, 'memory.md');
  if (fs.existsSync(memoryPath)) {
    const userMem = fs.readFileSync(memoryPath, 'utf8');
    const userIds = new Set(extractEntryIds(userMem));
    const required = ['M-NEXUS-P3'];
    const missing = required.filter((id) => !userIds.has(id));
    if (missing.length) {
      issues.push(`  ✗ memory.md: 시스템 entry [${missing.join(',')}] 누락 → npx walwal-harness migrate`);
      fail++;
    } else {
      pass++;
      log('  memory.md: 시스템 entry OK');
    }
  }

  // 5) deprecated user-facing slash commands
  const deprecated = path.join(PROJECT_ROOT, '.claude', 'commands', 'harness-next.md');
  if (fs.existsSync(deprecated)) {
    issues.push('  ⚠ .claude/commands/harness-next.md 존재 — v6.0.3 부터 회사 내부 도구로 전환됨. `npx walwal-harness --force` 또는 직접 삭제 권장');
  }

  console.log('');
  if (fail === 0) {
    log(`✓ Verify PASS — ${pass} 개 invariant 통과.`);
  } else {
    log(`✖ Verify FAIL — ${fail} 개 issue 발견:`);
    for (const i of issues) console.log(i);
  }
  console.log('');
}

function main() {
  if (isHelp) {
    showHelp();
    return;
  }

  if (subcommand === 'migrate') {
    runMigrate({ dryRun: args.includes('--dry-run') });
    return;
  }

  if (subcommand === 'verify') {
    runVerify();
    return;
  }

  // Legacy subcommands — removed as of v6.x (always-on company mode).
  if (subcommand === 'company' || subcommand === 'studio' ||
      subcommand === 'studio-v4' || subcommand === 'v4') {
    log(`NOTE: "${subcommand}" subcommand was removed.`);
    log('회사모드는 항상 켜져 있는 기본 런타임입니다. 별도 launch 명령은 필요 없습니다.');
    log('  - turn 자동 연쇄: Stop 훅 (자동)');
    log('  - 1시간 안전망 wake: bash scripts/harness-wake-install.sh install .');
    log('  - 시각화: bash scripts/harness-dashboard-up.sh');
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
  installStopHook();
  installAgentTeamsEnv();
  setupAgentsMd();
  checkPlaywrightMcp();
  checkRecommendedSkills();

  // v6.0 — propose migration if existing project is on v3
  const migFlags = detectMigrationNeeded();
  const gotchaMissing = Object.keys(migFlags.gotchaMissingEntries || {}).length > 0;
  const hasContentDrift =
    migFlags.progressV3toV4 ||
    migFlags.configMissingCompanyMode ||
    (migFlags.memoryMissingSystemEntries && migFlags.memoryMissingSystemEntries.length) ||
    gotchaMissing;
  if (hasContentDrift) {
    showMigrationProposal(migFlags);
  } else if (migFlags.bundleVersionStale) {
    // 콘텐츠 드리프트 없이 stamp 만 누락/오래됨 → 정합성 차원에서 직접 갱신.
    try {
      const pkg = JSON.parse(fs.readFileSync(path.join(PKG_ROOT, 'package.json'), 'utf8'));
      fs.writeFileSync(path.join(HARNESS_DIR, '.bundle-version'), pkg.version + '\n');
    } catch {}
  }

  // v6.0 — Brick Office dashboard one-liner
  console.log('');
  console.log('╔══════════════════════════════════════════════════════════╗');
  console.log('║  Brick Office — 라이브 운영 대시보드 (선택)              ║');
  console.log('╚══════════════════════════════════════════════════════════╝');
  console.log('  bash scripts/harness-dashboard-up.sh');
  console.log('  → http://localhost:3001 에서 .harness/ 상태 실시간 시각화');
  console.log('');

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
    log('║  기본은 회사모드: 병렬 · 자율 진행. 추가 입력 불필요.     ║');
    log('╚═══════════════════════════════════════════════════════════╝');
  } else {
    log('Next steps:');
    log('  1. Restart Claude/Codex if command discovery needs refresh.');
    log('  2. Use /goal or /hot-fix.');
    log('  3. Internal agents call hired agents/skills, not slash commands.');
  }
  console.log('');
}

main();
