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
// 1. .harness/ scaffolding
// ─────────────────────────────────────────
function scaffoldHarness() {
  log('Scaffolding .harness/ directory...');

  // Core directories
  ensureDir(path.join(HARNESS_DIR, 'actions'));
  ensureDir(path.join(HARNESS_DIR, 'archive'));
  ensureDir(path.join(HARNESS_DIR, 'gotchas'));

  // Copy gotchas initial files
  const gotchasSrc = path.join(PKG_ROOT, 'gotchas');
  if (fs.existsSync(gotchasSrc)) {
    const files = fs.readdirSync(gotchasSrc);
    for (const file of files) {
      const dest = path.join(HARNESS_DIR, 'gotchas', file);
      if (!fileExists(dest) || isForce) {
        copyFile(path.join(gotchasSrc, file), dest);
      }
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

  // Copy config.json
  const configSrc = path.join(PKG_ROOT, 'assets', 'templates', 'config.json');
  const configDest = path.join(HARNESS_DIR, 'config.json');
  if (fs.existsSync(configSrc) && (!fileExists(configDest) || isForce)) {
    copyFile(configSrc, configDest);
  }

  // Copy HARNESS.md
  const harnessMdSrc = path.join(PKG_ROOT, 'assets', 'templates', 'HARNESS.md');
  const harnessMdDest = path.join(HARNESS_DIR, 'HARNESS.md');
  if (fs.existsSync(harnessMdSrc) && (!fileExists(harnessMdDest) || isForce)) {
    copyFile(harnessMdSrc, harnessMdDest);
  }

  // Copy memory.md (shared learnings)
  const memorySrc = path.join(PKG_ROOT, 'assets', 'templates', 'memory.md');
  const memoryDest = path.join(HARNESS_DIR, 'memory.md');
  if (fs.existsSync(memorySrc) && (!fileExists(memoryDest) || isForce)) {
    copyFile(memorySrc, memoryDest);
  }

  // Copy CONVENTIONS.md to project root
  const conventionsSrc = path.join(PKG_ROOT, 'assets', 'templates', 'CONVENTIONS.md');
  const conventionsDest = path.join(PROJECT_ROOT, 'CONVENTIONS.md');
  if (fs.existsSync(conventionsSrc) && (!fileExists(conventionsDest) || isForce)) {
    copyFile(conventionsSrc, conventionsDest);
    log('CONVENTIONS.md created — edit to define your project conventions');
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

  const skills = fs.readdirSync(skillsSrc, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);

  for (const skill of skills) {
    const src = path.join(skillsSrc, skill);
    const dest = path.join(CLAUDE_SKILLS_DIR, `harness-${skill}`);

    if (!fileExists(dest) || isForce) {
      copyDir(src, dest);
      log(`  Installed: harness-${skill}`);
    } else {
      log(`  Skipped (exists): harness-${skill}`);
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

  if (fs.existsSync(scriptsSrc)) {
    ensureDir(scriptsDest);
    const entries = fs.readdirSync(scriptsSrc, { withFileTypes: true });
    for (const entry of entries) {
      const srcPath = path.join(scriptsSrc, entry.name);
      const destPath = path.join(scriptsDest, entry.name);
      if (entry.isDirectory()) {
        // Copy subdirectories (e.g., lib/)
        if (!fileExists(destPath) || isForce) {
          copyDir(srcPath, destPath);
          // Make scripts in subdirs executable
          try {
            const subFiles = fs.readdirSync(destPath);
            for (const f of subFiles) {
              if (f.endsWith('.sh')) {
                fs.chmodSync(path.join(destPath, f), '755');
              }
            }
          } catch (e) {}
        }
      } else {
        if (!fileExists(destPath) || isForce) {
          copyFile(srcPath, destPath);
          try { fs.chmodSync(destPath, '755'); } catch (e) {}
        }
      }
    }
  }

  log('Scripts installation complete');
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
  npx walwal-harness            Initialize project for harness engineering
  npx walwal-harness --force    Re-initialize (overwrites existing files)
  npx walwal-harness studio     Launch Harness Studio (tmux 4-pane monitor)
  npx walwal-harness studio --ai  Studio + AI eval summary (API cost)
  npx walwal-harness --help     Show this help

What it does:
  1. Scaffolds .harness/ directory (actions, archive, gotchas, config)
  2. Installs skills to .claude/skills/ (dispatcher, planner, generators, evaluators)
  3. Copies helper scripts to scripts/
  4. Registers SessionStart hook (compact boot-time status)
  5. Installs statusline (persistent 1-line status bar at terminal bottom)
  6. Registers UserPromptSubmit hook (auto-route every prompt through harness-dispatcher)
  7. Creates AGENTS.md + CLAUDE.md symlink
  8. Checks Playwright MCP configuration
  9. Checks recommended external skills (Vercel, design skills)

Auto routing:
  Every user prompt is routed through harness-dispatcher.
  Per-message opt-out: say "harness skip" or "harness 없이".
  Global disable: edit .harness/config.json → behavior.auto_route_dispatcher = false

After init:
  1. Restart Claude Code session (exit and re-enter) for skills to load
  2. Say "하네스 엔지니어링 시작" or invoke /harness-dispatcher
`);
}

// ─────────────────────────────────────────
// Main
// ─────────────────────────────────────────
function runStudio() {
  const useAi = args.includes('--ai') ? '--ai' : '';
  const scriptsDir = path.join(PKG_ROOT, 'scripts');
  const tmuxScript = path.join(scriptsDir, 'harness-tmux.sh');

  if (!fs.existsSync(tmuxScript)) {
    log('ERROR: harness-tmux.sh not found. Update @walwal-harness/cli to >= 3.6.0');
    process.exit(1);
  }

  try {
    execSync('which tmux', { stdio: 'ignore' });
  } catch {
    log('ERROR: tmux is required. Install with: brew install tmux');
    process.exit(1);
  }

  const cmd = `bash "${tmuxScript}" "${PROJECT_ROOT}" ${useAi}`.trim();
  log(`Launching Harness Studio...`);
  execSync(cmd, { stdio: 'inherit' });
}

function main() {
  if (isHelp) {
    showHelp();
    return;
  }

  if (subcommand === 'studio') {
    runStudio();
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
  installSessionHook();
  installStatusline();
  installUserPromptSubmitHook();
  setupAgentsMd();
  checkPlaywrightMcp();
  checkRecommendedSkills();

  console.log('');
  log('═══ Initialization Complete ═══');
  log('');

  if (isAuto) {
    // postinstall context — Claude Code is likely already running
    log('╔═══════════════════════════════════════════════════════════╗');
    log('║  IMPORTANT: Restart Claude Code for skills to activate!  ║');
    log('║                                                          ║');
    log('║  Claude Code discovers skills at session startup.        ║');
    log('║  Type /exit, then re-enter this directory to begin.      ║');
    log('║                                                          ║');
    log('║  Then say: "하네스 엔지니어링 시작"                        ║');
    log('║  Or invoke: /harness-dispatcher                          ║');
    log('╚═══════════════════════════════════════════════════════════╝');
  } else {
    log('Next steps:');
    log('  1. Restart Claude Code session (/exit → re-enter directory)');
    log('  2. Say "하네스 엔지니어링 시작" or invoke /harness-dispatcher');
  }
  console.log('');
}

main();
