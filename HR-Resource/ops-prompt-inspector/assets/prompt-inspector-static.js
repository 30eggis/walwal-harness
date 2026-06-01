(function () {
  const VERSION = '1.2.0-static';
  const ID = 'harness-ops-prompt-inspector';
  if (window.__HARNESS_OPS_PROMPT_INSPECTOR__) return;
  window.__HARNESS_OPS_PROMPT_INSPECTOR__ = { version: VERSION };

  const state = {
    selecting: false,
    target: null,
    bindings: [],
  };

  const css = `
    #${ID}-bar{position:fixed;right:18px;bottom:18px;z-index:2147483647;display:flex;gap:8px;align-items:center;background:#111827;color:#fff;border:1px solid #374151;border-radius:8px;padding:10px;box-shadow:0 16px 36px rgba(0,0,0,.32);font:13px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
    #${ID}-bar button,#${ID}-panel button{border:0;border-radius:6px;padding:8px 10px;background:#2563eb;color:#fff;cursor:pointer;font:inherit}
    #${ID}-bar button.secondary,#${ID}-panel button.secondary{background:#374151}
    #${ID}-bar button.danger{background:#dc2626}
    #${ID}-panel{position:fixed;right:18px;bottom:76px;width:min(420px,calc(100vw - 36px));z-index:2147483647;background:#fff;color:#111827;border:1px solid #d1d5db;border-radius:8px;box-shadow:0 18px 48px rgba(0,0,0,.28);padding:14px;font:13px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
    #${ID}-panel h3{margin:0 0 10px;font-size:15px}
    #${ID}-panel label{display:block;margin:10px 0 4px;color:#374151;font-weight:600}
    #${ID}-panel input,#${ID}-panel textarea,#${ID}-panel select{width:100%;box-sizing:border-box;border:1px solid #d1d5db;border-radius:6px;padding:8px;font:inherit}
    #${ID}-panel textarea{min-height:72px;resize:vertical}
    #${ID}-panel .row{display:flex;gap:8px;margin-top:12px}
    #${ID}-highlight{position:fixed;z-index:2147483646;pointer-events:none;border:2px solid #f59e0b;background:rgba(245,158,11,.12);border-radius:4px}
    .${ID}-badge{position:absolute;z-index:2147483645;background:#f59e0b;color:#111827;border-radius:999px;padding:2px 7px;font:11px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;box-shadow:0 2px 8px rgba(0,0,0,.24)}
  `;

  const style = document.createElement('style');
  style.textContent = css;
  document.head.appendChild(style);

  const bar = document.createElement('div');
  bar.id = `${ID}-bar`;
  bar.innerHTML = `
    <strong>Prompt Inspector</strong>
    <button type="button" data-action="select">Select</button>
    <button type="button" class="secondary" data-action="export">Export</button>
    <button type="button" class="danger" data-action="clear">Clear</button>
  `;
  document.body.appendChild(bar);

  const highlight = document.createElement('div');
  highlight.id = `${ID}-highlight`;
  highlight.hidden = true;
  document.body.appendChild(highlight);

  function selectorFor(el) {
    if (!el || el === document.body) return 'body';
    if (el.id) return `#${CSS.escape(el.id)}`;
    const parts = [];
    let node = el;
    while (node && node.nodeType === 1 && node !== document.body && parts.length < 4) {
      let part = node.tagName.toLowerCase();
      if (node.classList && node.classList.length) {
        part += `.${Array.from(node.classList).slice(0, 2).map((c) => CSS.escape(c)).join('.')}`;
      }
      const parent = node.parentElement;
      if (parent) {
        const same = Array.from(parent.children).filter((child) => child.tagName === node.tagName);
        if (same.length > 1) part += `:nth-of-type(${same.indexOf(node) + 1})`;
      }
      parts.unshift(part);
      node = parent;
    }
    return parts.join(' > ');
  }

  function positionHighlight(el) {
    if (!el) {
      highlight.hidden = true;
      return;
    }
    const rect = el.getBoundingClientRect();
    highlight.hidden = false;
    highlight.style.left = `${rect.left}px`;
    highlight.style.top = `${rect.top}px`;
    highlight.style.width = `${rect.width}px`;
    highlight.style.height = `${rect.height}px`;
  }

  function panelFor(el) {
    const selector = selectorFor(el);
    const panel = document.createElement('div');
    panel.id = `${ID}-panel`;
    panel.innerHTML = `
      <h3>Bind selected element</h3>
      <label>Selector</label>
      <input value="${selector.replace(/"/g, '&quot;')}" data-field="selector">
      <label>Mode</label>
      <select data-field="mode">
        <option value="comment">Comment Only</option>
        <option value="api">Connect API</option>
      </select>
      <label>API / Note</label>
      <input placeholder="GET /api/example or short title" data-field="api">
      <label>Comment</label>
      <textarea placeholder="Describe intended behavior, visual issue, or API binding." data-field="comment"></textarea>
      <div class="row">
        <button type="button" data-action="save">Save</button>
        <button type="button" class="secondary" data-action="cancel">Cancel</button>
      </div>
    `;
    document.body.appendChild(panel);
    panel.querySelector('[data-action="save"]').addEventListener('click', () => {
      const binding = {
        route: `${location.pathname}${location.hash || ''}`,
        selector: panel.querySelector('[data-field="selector"]').value,
        mode: panel.querySelector('[data-field="mode"]').value,
        api: panel.querySelector('[data-field="api"]').value.trim(),
        comment: panel.querySelector('[data-field="comment"]').value.trim(),
      };
      state.bindings.push(binding);
      addBadge(el, state.bindings.length);
      panel.remove();
      state.target = null;
      positionHighlight(null);
    });
    panel.querySelector('[data-action="cancel"]').addEventListener('click', () => {
      panel.remove();
      state.target = null;
      positionHighlight(null);
    });
  }

  function addBadge(el, index) {
    const rect = el.getBoundingClientRect();
    const badge = document.createElement('div');
    badge.className = `${ID}-badge`;
    badge.textContent = `PI-${index}`;
    badge.style.left = `${Math.max(6, rect.left + window.scrollX)}px`;
    badge.style.top = `${Math.max(6, rect.top + window.scrollY - 20)}px`;
    document.body.appendChild(badge);
  }

  function exportMarkdown() {
    const lines = [`# Prompt Inspector`, ``, `Route: ${location.pathname}${location.hash || ''}`, ``];
    state.bindings.forEach((binding, i) => {
      lines.push(`## ${i + 1}. ${binding.mode === 'api' ? 'API Binding' : 'Comment'}`);
      lines.push(`- Selector: \`${binding.selector}\``);
      if (binding.api) lines.push(`- API: ${binding.api}`);
      if (binding.comment) lines.push(`- Comment: ${binding.comment}`);
      lines.push('');
    });
    const markdown = lines.join('\n');
    navigator.clipboard?.writeText(markdown).catch(() => {});
    console.log(markdown);
    alert(`Prompt Inspector export copied/logged. Bindings: ${state.bindings.length}`);
  }

  document.addEventListener('mouseover', (event) => {
    if (!state.selecting || bar.contains(event.target)) return;
    positionHighlight(event.target);
  }, true);

  document.addEventListener('click', (event) => {
    if (!state.selecting || bar.contains(event.target)) return;
    event.preventDefault();
    event.stopPropagation();
    state.selecting = false;
    state.target = event.target;
    bar.querySelector('[data-action="select"]').textContent = 'Select';
    document.getElementById(`${ID}-panel`)?.remove();
    panelFor(event.target);
  }, true);

  bar.addEventListener('click', (event) => {
    const action = event.target && event.target.getAttribute('data-action');
    if (action === 'select') {
      state.selecting = !state.selecting;
      event.target.textContent = state.selecting ? 'Selecting...' : 'Select';
      if (!state.selecting) positionHighlight(null);
    }
    if (action === 'export') exportMarkdown();
    if (action === 'clear') {
      state.bindings = [];
      document.querySelectorAll(`.${ID}-badge`).forEach((el) => el.remove());
      positionHighlight(null);
    }
  });
})();
