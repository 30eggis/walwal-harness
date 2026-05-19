#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const sourceRoot = process.argv[2] || '/Users/ted/Downloads/agency-agents-main';
const targetRoot = process.argv[3] || path.resolve(process.cwd(), 'HR-Resource');

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.isFile() && entry.name.endsWith('.md')) out.push(full);
  }
  return out;
}

function slugify(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function parseFrontmatter(content) {
  const match = /^---\n([\s\S]*?)\n---\n?/.exec(content);
  if (!match) return null;
  const frontmatter = match[1];
  const fields = {};
  for (const line of frontmatter.split('\n')) {
    const m = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
    if (m) fields[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
  return { frontmatter, fields, body: content.slice(match[0].length) };
}

function hasAgentShape(parsed) {
  return Boolean(parsed && parsed.fields.name && parsed.fields.description);
}

function convertFile(file) {
  const content = fs.readFileSync(file, 'utf8');
  const parsed = parseFrontmatter(content);
  if (!hasAgentShape(parsed)) return null;

  const sourceRel = path.relative(sourceRoot, file);
  const sourceSlug = slugify(sourceRel.replace(/\.md$/, ''));
  const agentName = slugify(parsed.fields.name);
  const skillName = sourceSlug || agentName;
  const destDir = path.join(targetRoot, skillName);
  const dest = path.join(destDir, 'SKILL.md');

  const description = parsed.fields.description.replace(/"/g, '\\"');
  const body = parsed.body.replace(/^# /, `# ${parsed.fields.name}\n\n`);
  const skill = [
    '---',
    `name: ${skillName}`,
    `description: "${description}"`,
    'model: sonnet',
    'disable-model-invocation: false',
    '---',
    '',
    '<!--',
    `Imported from agency-agents: ${sourceRel}`,
    'Original frontmatter:',
    parsed.frontmatter,
    '-->',
    '',
    body.trim(),
    '',
    '## Harness Operating Contract',
    '',
    '- You are a hireable HR-Resource worker, not a CXX executive.',
    '- Work only after a CXX assigns a mission through `/hiring` and `/resource-manager` wiring.',
    '- Start each assignment from fresh context.',
    '- Record mission output in `.harness/documents/{goal-or-child-mission}/{owning-cxx}/workers/{name}.md` unless the requester specifies another mission document.',
    '- Follow DDD boundaries for domain, application, infrastructure, and interface decisions.',
    ''
  ].join('\n');

  fs.mkdirSync(destDir, { recursive: true });
  fs.writeFileSync(dest, skill);
  return { sourceRel, skillName };
}

const converted = [];
for (const file of walk(sourceRoot)) {
  const result = convertFile(file);
  if (result) converted.push(result);
}

converted.sort((a, b) => a.skillName.localeCompare(b.skillName));
const index = {
  source: sourceRoot,
  imported_at: new Date().toISOString(),
  count: converted.length,
  resources: converted
};
fs.mkdirSync(targetRoot, { recursive: true });
fs.writeFileSync(path.join(targetRoot, 'index.json'), JSON.stringify(index, null, 2) + '\n');

console.log(`Imported ${converted.length} agency agents into ${targetRoot}`);
