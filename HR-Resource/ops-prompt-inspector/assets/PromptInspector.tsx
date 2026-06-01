'use client';

// Prompt Inspector v1.1.0 - API Search Feature
export const PROMPT_INSPECTOR_VERSION = '1.1.0';

import React, { useState, useCallback, useEffect } from 'react';

// ============================================================================
// Types
// ============================================================================

interface APIEndpoint {
  id: string;
  method: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';
  path: string;
  description?: string;
}

interface TriggerType {
  id: string;
  label: string;
  icon: string;
  description: string;
}

interface HandlerType {
  id: string;
  label: string;
  description: string;
}

interface ErrorHandler {
  id: number;
  type: HandlerType;
  message: string;
  errorCode?: string;
  redirectPath?: string;
}

interface Binding {
  mode: 'comment' | 'api';
  elementSelector: string;
  elementDescription?: string;
  comment?: string;
  api?: APIEndpoint;
  trigger?: TriggerType;
  successHandler?: {
    type: HandlerType;
    message: string;
    redirectPath?: string;
  };
  errorHandlers?: ErrorHandler[];
}

interface PromptInspectorProps {
  apis?: APIEndpoint[];
  onBindingComplete?: (binding: Binding) => void;
  onExportMarkdown?: (markdown: string) => void;
}

// ============================================================================
// Constants
// ============================================================================

const BINDING_MODES = [
  { id: 'comment', label: 'Comment Only', description: 'Leave a comment or annotation on this element' },
  { id: 'api', label: 'Connect API', description: 'Bind an API call to this element' },
];

const TRIGGER_TYPES: TriggerType[] = [
  { id: 'onComponentMount', label: 'Mount', icon: '🔄', description: 'Component loaded' },
  { id: 'onPageLoad', label: 'Page Load', icon: '📄', description: 'Page initially loads' },
  { id: 'onClick', label: 'Click', icon: '👆', description: 'Element clicked' },
  { id: 'onSubmit', label: 'Submit', icon: '📤', description: 'Form submitted' },
  { id: 'onBlur', label: 'Blur', icon: '👁️', description: 'Input loses focus' },
  { id: 'onChange', label: 'Change', icon: '✏️', description: 'Value changes' },
];

const HANDLER_TYPES: HandlerType[] = [
  { id: 'toast', label: 'Toast Message', description: 'Brief notification' },
  { id: 'popup', label: 'Popup Dialog', description: 'Modal dialog' },
  { id: 'redirect', label: 'Page Redirect', description: 'Navigate to page' },
  { id: 'none', label: 'None', description: 'No feedback' },
];

// ============================================================================
// Component
// ============================================================================

export function PromptInspector({
  apis = [],
  onBindingComplete,
  onExportMarkdown,
}: PromptInspectorProps) {
  const [isSelecting, setIsSelecting] = useState(false);
  const [highlightRect, setHighlightRect] = useState<DOMRect | null>(null);
  const [showPanel, setShowPanel] = useState(false);
  const [panelStep, setPanelStep] = useState<'mode' | 'comment' | 'api'>('mode');
  const [bindings, setBindings] = useState<Binding[]>([]);
  const [badgePositions, setBadgePositions] = useState<Array<{ index: number; top: number; left: number; mode: string }>>([]);
  const [routePath, setRoutePath] = useState(typeof window !== 'undefined' ? window.location.pathname : '/');
  const [apiSearchQuery, setApiSearchQuery] = useState('');
  const [isApiDropdownOpen, setIsApiDropdownOpen] = useState(false);

  const [currentBinding, setCurrentBinding] = useState<Partial<Binding>>({
    mode: undefined,
    comment: '',
    trigger: TRIGGER_TYPES[2],
    successHandler: { type: HANDLER_TYPES[0], message: 'Successfully completed.' },
    errorHandlers: [{ id: 1, type: HANDLER_TYPES[0], message: 'An error occurred.', errorCode: '' }],
  });

  // Update badge positions
  useEffect(() => {
    const updatePositions = () => {
      const positions = bindings.map((binding, index) => {
        try {
          const element = document.querySelector(binding.elementSelector);
          if (element) {
            const rect = element.getBoundingClientRect();
            return { index: index + 1, top: rect.top + window.scrollY, left: rect.left + window.scrollX, mode: binding.mode };
          }
        } catch {}
        return null;
      }).filter(Boolean) as Array<{ index: number; top: number; left: number; mode: string }>;
      setBadgePositions(positions);
    };

    updatePositions();
    window.addEventListener('scroll', updatePositions);
    window.addEventListener('resize', updatePositions);
    return () => {
      window.removeEventListener('scroll', updatePositions);
      window.removeEventListener('resize', updatePositions);
    };
  }, [bindings]);

  // CSS selector generator - handles Tailwind CSS special characters
  const getSelector = useCallback((element: HTMLElement): string => {
    // 1. Try ID selector first (most reliable)
    if (element.id) {
      const escapedId = CSS.escape(element.id);
      return `#${escapedId}`;
    }

    // 2. Try data attributes (great for component identification)
    const dataTestId = element.getAttribute('data-testid') || element.getAttribute('data-id');
    if (dataTestId) {
      return `[data-testid="${dataTestId}"]`;
    }

    // 3. Try clean class names (filter out Tailwind special chars)
    const invalidChars = /[:\[\]\/&@!%]/;
    const cleanClasses = Array.from(element.classList).filter(
      c => !c.startsWith('_') && !invalidChars.test(c)
    );

    if (cleanClasses.length > 0) {
      const escapedClasses = cleanClasses.map(c => CSS.escape(c)).join('.');
      const selector = `${element.tagName.toLowerCase()}.${escapedClasses}`;
      try {
        if (document.querySelectorAll(selector).length === 1) return selector;
      } catch {
        // Invalid selector, continue to path-based approach
      }
    }

    // 4. Try combining tag + text content for buttons/links
    const tag = element.tagName.toLowerCase();
    const text = element.textContent?.trim().slice(0, 30);
    if (['button', 'a', 'label'].includes(tag) && text) {
      // Use XPath-like text matching via attribute selector workaround
      const ariaLabel = element.getAttribute('aria-label');
      if (ariaLabel) {
        return `${tag}[aria-label="${CSS.escape(ariaLabel)}"]`;
      }
    }

    // 5. Fall back to path-based selector (most reliable)
    const path: string[] = [];
    let current: HTMLElement | null = element;
    while (current && current !== document.body) {
      let selector = current.tagName.toLowerCase();

      if (current.id) {
        path.unshift(`#${CSS.escape(current.id)}`);
        break;
      }

      // Add nth-child for disambiguation
      const siblings = current.parentElement?.children;
      if (siblings && siblings.length > 1) {
        const sameTagSiblings = Array.from(siblings).filter(
          s => s.tagName === current!.tagName
        );
        if (sameTagSiblings.length > 1) {
          const index = sameTagSiblings.indexOf(current) + 1;
          selector += `:nth-of-type(${index})`;
        }
      }

      path.unshift(selector);
      current = current.parentElement;
    }
    return path.join(' > ');
  }, []);

  // Selection handlers
  useEffect(() => {
    if (!isSelecting) return;

    const handleMouseMove = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      if (target.closest('[data-prompt-inspector-ignore]')) return;
      setHighlightRect(target.getBoundingClientRect());
    };

    const handleClick = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      if (target.closest('[data-prompt-inspector-ignore]')) return;
      e.preventDefault();
      e.stopPropagation();

      const selector = getSelector(target);
      setCurrentBinding(prev => ({
        ...prev,
        elementSelector: selector,
        elementDescription: target.textContent?.slice(0, 50) || undefined,
      }));
      setIsSelecting(false);
      setHighlightRect(null);
      setPanelStep('mode');
      setShowPanel(true);
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('click', handleClick, true);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('click', handleClick, true);
    };
  }, [isSelecting, getSelector]);

  const selectMode = (mode: typeof BINDING_MODES[0]) => {
    setCurrentBinding(prev => ({ ...prev, mode: mode.id as 'comment' | 'api' }));
    setPanelStep(mode.id as 'comment' | 'api');
  };

  const resetPanel = (continueSelecting = false) => {
    setShowPanel(false);
    setPanelStep('mode');
    setCurrentBinding({
      mode: undefined,
      comment: '',
      trigger: TRIGGER_TYPES[2],
      successHandler: { type: HANDLER_TYPES[0], message: 'Successfully completed.' },
      errorHandlers: [{ id: 1, type: HANDLER_TYPES[0], message: 'An error occurred.', errorCode: '' }],
    });
    setApiSearchQuery('');
    setIsApiDropdownOpen(false);
    if (continueSelecting) setIsSelecting(true);
  };

  // Filter APIs based on search query
  const filteredApis = apis.filter(api => {
    if (!apiSearchQuery.trim()) return true;
    const query = apiSearchQuery.toLowerCase();
    return (
      api.method.toLowerCase().includes(query) ||
      api.path.toLowerCase().includes(query) ||
      (api.description?.toLowerCase().includes(query) ?? false)
    );
  });

  // Close API dropdown when clicking outside
  useEffect(() => {
    if (!isApiDropdownOpen) return;
    const handleClickOutside = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      if (!target.closest('[data-api-search]')) {
        setIsApiDropdownOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isApiDropdownOpen]);

  const completeBinding = () => {
    if (!currentBinding.elementSelector) return;
    if (currentBinding.mode === 'api' && !currentBinding.api) return;

    const binding = currentBinding as Binding;
    setBindings(prev => [...prev, binding]);
    onBindingComplete?.(binding);
    resetPanel(true);
  };

  const addErrorHandler = () => {
    setCurrentBinding(prev => ({
      ...prev,
      errorHandlers: [...(prev.errorHandlers || []), { id: Date.now(), type: HANDLER_TYPES[0], message: '', errorCode: '' }],
    }));
  };

  const removeErrorHandler = (id: number) => {
    setCurrentBinding(prev => ({
      ...prev,
      errorHandlers: prev.errorHandlers?.filter(h => h.id !== id),
    }));
  };

  const updateErrorHandler = (id: number, field: string, value: any) => {
    setCurrentBinding(prev => ({
      ...prev,
      errorHandlers: prev.errorHandlers?.map(h => h.id === id ? { ...h, [field]: value } : h),
    }));
  };

  const exportMarkdown = () => {
    const lines = [`# Route: ${routePath}`, ''];
    bindings.forEach((binding, index) => {
      const num = index + 1;
      if (binding.mode === 'comment') {
        lines.push(`## ${num}. Comment`);
        lines.push(`- Selector: \`${binding.elementSelector}\``);
        lines.push(`- Comment: ${binding.comment}`);
      } else {
        lines.push(`## ${num}. ${binding.api?.method} ${binding.api?.path}`);
        lines.push(`- Selector: \`${binding.elementSelector}\``);
        lines.push(`- Trigger: ${binding.trigger?.id}`);
        if (binding.successHandler?.type.id !== 'none') {
          lines.push(`- OnSuccess: ${binding.successHandler?.type.id}${binding.successHandler?.message ? ` ("${binding.successHandler.message}")` : ''}${binding.successHandler?.redirectPath ? ` → ${binding.successHandler.redirectPath}` : ''}`);
        }
        binding.errorHandlers?.forEach((handler, i) => {
          if (handler.type.id !== 'none') {
            const errorCodePart = handler.errorCode ? `[${handler.errorCode}] ` : '';
            lines.push(`- OnError${(binding.errorHandlers?.length || 0) > 1 ? ` #${i + 1}` : ''}: ${errorCodePart}${handler.type.id}${handler.message ? ` ("${handler.message}")` : ''}${handler.redirectPath ? ` → ${handler.redirectPath}` : ''}`);
          }
        });
      }
      lines.push('');
    });
    const markdown = lines.join('\n');
    navigator.clipboard.writeText(markdown);
    onExportMarkdown?.(markdown);
    alert('Copied to clipboard!\n\n' + markdown);
  };

  // Styles
  const styles = {
    overlay: { position: 'fixed' as const, inset: 0, backgroundColor: 'rgba(0,0,0,0.3)', zIndex: 9998, pointerEvents: 'none' as const },
    toolbar: { position: 'fixed' as const, bottom: 20, right: 20, zIndex: 10000, display: 'flex', gap: 8, padding: 8, backgroundColor: '#1a1a2e', borderRadius: 12, boxShadow: '0 4px 20px rgba(0,0,0,0.3)' },
    button: { padding: '10px 16px', border: 'none', borderRadius: 8, cursor: 'pointer', fontSize: 14, fontWeight: 500 },
    highlight: { position: 'fixed' as const, pointerEvents: 'none' as const, border: '3px solid #6366f1', backgroundColor: 'rgba(99,102,241,0.2)', borderRadius: 4, zIndex: 9997 },
    panel: { position: 'fixed' as const, top: '50%', left: '50%', transform: 'translate(-50%,-50%)', zIndex: 10001, width: 520, maxHeight: '85vh', overflow: 'auto', backgroundColor: '#1a1a2e', borderRadius: 16, boxShadow: '0 8px 32px rgba(0,0,0,0.4)', color: 'white' },
    sectionTitle: { fontSize: 12, fontWeight: 600, color: '#9ca3af', marginBottom: 12, textTransform: 'uppercase' as const, letterSpacing: '0.5px' },
    select: { width: '100%', padding: 12, backgroundColor: '#374151', border: '1px solid #4b5563', borderRadius: 8, color: 'white', fontSize: 14 },
    input: { width: '100%', padding: 12, backgroundColor: '#374151', border: '1px solid #4b5563', borderRadius: 8, color: 'white', fontSize: 14, boxSizing: 'border-box' as const },
    badge: { position: 'absolute' as const, width: 24, height: 24, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, fontWeight: 700, color: 'white', zIndex: 9990, boxShadow: '0 2px 8px rgba(0,0,0,0.3)', transform: 'translate(-50%,-50%)' },
    modeCard: { display: 'flex', alignItems: 'center', gap: 16, padding: 16, backgroundColor: '#374151', borderRadius: 12, cursor: 'pointer', border: '2px solid transparent' },
  };

  return (
    <div data-prompt-inspector-ignore>
      {isSelecting && <div style={styles.overlay} />}
      {isSelecting && highlightRect && (
        <div style={{ ...styles.highlight, top: highlightRect.top, left: highlightRect.left, width: highlightRect.width, height: highlightRect.height }} />
      )}

      {/* Badges */}
      {badgePositions.map((pos) => (
        <div key={pos.index} style={{ ...styles.badge, top: pos.top, left: pos.left, backgroundColor: pos.mode === 'comment' ? '#f59e0b' : '#6366f1' }} title={`Binding #${pos.index}`}>
          {pos.index}
        </div>
      ))}

      {/* Panel Backdrop */}
      {showPanel && <div style={{ position: 'fixed', inset: 0, zIndex: 10000 }} onClick={() => resetPanel(true)} />}

      {/* Toolbar */}
      <div style={styles.toolbar}>
        <input
          style={{ padding: '8px 12px', backgroundColor: '#374151', border: '1px solid #4b5563', borderRadius: 8, color: 'white', fontSize: 13, width: 150 }}
          value={routePath}
          onChange={(e) => setRoutePath(e.target.value)}
          placeholder="/route/path"
        />
        <button
          style={{ ...styles.button, backgroundColor: isSelecting ? '#22c55e' : '#6366f1', color: 'white' }}
          onClick={() => setIsSelecting(!isSelecting)}
        >
          {isSelecting ? 'Selecting...' : 'Select Element'}
        </button>
        {bindings.length > 0 && (
          <button style={{ ...styles.button, backgroundColor: '#374151', color: 'white' }} onClick={exportMarkdown}>
            Export ({bindings.length})
          </button>
        )}
      </div>

      {/* Panel */}
      {showPanel && (
        <div style={styles.panel} onClick={(e) => e.stopPropagation()}>
          <div style={{ padding: 20, borderBottom: '1px solid #374151' }}>
            <h2 style={{ margin: 0, fontSize: 18 }}>
              {panelStep === 'mode' && 'Choose Action'}
              {panelStep === 'comment' && 'Add Comment'}
              {panelStep === 'api' && 'Configure API Binding'}
            </h2>
            {currentBinding.elementSelector && (
              <div style={{ display: 'inline-block', padding: '4px 8px', backgroundColor: '#6366f1', borderRadius: 4, fontSize: 12, fontFamily: 'monospace', marginTop: 8 }}>
                {currentBinding.elementSelector}
              </div>
            )}
          </div>

          <div style={{ padding: 20 }}>
            {/* Mode Selection */}
            {panelStep === 'mode' && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {BINDING_MODES.map(mode => (
                  <div key={mode.id} style={styles.modeCard} onClick={() => selectMode(mode)}>
                    <div style={{ width: 48, height: 48, borderRadius: 12, backgroundColor: mode.id === 'comment' ? '#f59e0b' : '#6366f1', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24 }}>
                      {mode.id === 'comment' ? '💬' : '🔗'}
                    </div>
                    <div>
                      <div style={{ fontWeight: 600, fontSize: 16 }}>{mode.label}</div>
                      <div style={{ fontSize: 13, color: '#9ca3af', marginTop: 4 }}>{mode.description}</div>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {/* Comment Mode */}
            {panelStep === 'comment' && (
              <>
                <div style={{ marginBottom: 24 }}>
                  <div style={styles.sectionTitle}>Your Comment</div>
                  <textarea
                    style={{ ...styles.input, minHeight: 120, resize: 'vertical' }}
                    placeholder="Enter your comment..."
                    value={currentBinding.comment || ''}
                    onChange={(e) => setCurrentBinding(prev => ({ ...prev, comment: e.target.value }))}
                  />
                </div>
                <div style={{ display: 'flex', gap: 12 }}>
                  <button style={{ ...styles.button, backgroundColor: '#6366f1', color: 'white', flex: 1, opacity: currentBinding.comment ? 1 : 0.5 }} disabled={!currentBinding.comment} onClick={completeBinding}>Add Comment</button>
                  <button style={{ ...styles.button, backgroundColor: '#374151', color: 'white' }} onClick={() => setPanelStep('mode')}>Back</button>
                  <button style={{ ...styles.button, backgroundColor: '#374151', color: 'white' }} onClick={() => resetPanel(false)}>Cancel</button>
                </div>
              </>
            )}

            {/* API Mode */}
            {panelStep === 'api' && (
              <>
                {/* API Selection with Search */}
                <div style={{ marginBottom: 24, position: 'relative' }} data-api-search>
                  <div style={styles.sectionTitle}>Select API ({apis.length} available)</div>
                  <div style={{ position: 'relative' }}>
                    <input
                      style={styles.input}
                      placeholder="🔍 Search APIs by method, path, or description..."
                      value={apiSearchQuery}
                      onChange={(e) => {
                        setApiSearchQuery(e.target.value);
                        setIsApiDropdownOpen(true);
                      }}
                      onFocus={() => setIsApiDropdownOpen(true)}
                    />
                    {apiSearchQuery && (
                      <button
                        style={{ position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', color: '#9ca3af', cursor: 'pointer', fontSize: 16, padding: 4 }}
                        onClick={() => { setApiSearchQuery(''); setIsApiDropdownOpen(true); }}
                        title="Clear search"
                      >
                        ✕
                      </button>
                    )}
                  </div>
                  {currentBinding.api && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 8, padding: '8px 12px', backgroundColor: '#6366f1', borderRadius: 8 }}>
                      <span style={{ fontWeight: 600, fontSize: 12 }}>{currentBinding.api.method}</span>
                      <span style={{ fontSize: 14 }}>{currentBinding.api.path}</span>
                      <button
                        style={{ marginLeft: 'auto', background: 'none', border: 'none', color: 'white', cursor: 'pointer', fontSize: 14, padding: 2 }}
                        onClick={() => setCurrentBinding(prev => ({ ...prev, api: undefined }))}
                        title="Remove selection"
                      >
                        ✕
                      </button>
                    </div>
                  )}
                  {isApiDropdownOpen && (
                    <div style={{ position: 'absolute', top: '100%', left: 0, right: 0, maxHeight: 240, overflow: 'auto', backgroundColor: '#2d3748', borderRadius: 8, marginTop: 4, boxShadow: '0 4px 12px rgba(0,0,0,0.3)', zIndex: 10 }}>
                      {filteredApis.length === 0 ? (
                        <div style={{ padding: 16, textAlign: 'center', color: '#9ca3af' }}>
                          {apiSearchQuery ? `No APIs matching "${apiSearchQuery}"` : 'No APIs available'}
                        </div>
                      ) : (
                        filteredApis.map(api => (
                          <div
                            key={api.id}
                            style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 12px', cursor: 'pointer', borderBottom: '1px solid #374151', backgroundColor: currentBinding.api?.id === api.id ? '#4b5563' : 'transparent' }}
                            onClick={() => {
                              setCurrentBinding(prev => ({ ...prev, api }));
                              setIsApiDropdownOpen(false);
                              setApiSearchQuery('');
                            }}
                            onMouseEnter={(e) => { (e.currentTarget as HTMLElement).style.backgroundColor = '#4b5563'; }}
                            onMouseLeave={(e) => { (e.currentTarget as HTMLElement).style.backgroundColor = currentBinding.api?.id === api.id ? '#4b5563' : 'transparent'; }}
                          >
                            <span style={{
                              padding: '2px 8px',
                              borderRadius: 4,
                              fontSize: 11,
                              fontWeight: 700,
                              backgroundColor: api.method === 'GET' ? '#10b981' : api.method === 'POST' ? '#3b82f6' : api.method === 'PUT' ? '#f59e0b' : api.method === 'DELETE' ? '#ef4444' : '#8b5cf6',
                              color: 'white',
                              minWidth: 50,
                              textAlign: 'center'
                            }}>
                              {api.method}
                            </span>
                            <div style={{ flex: 1, minWidth: 0 }}>
                              <div style={{ fontSize: 14, fontFamily: 'monospace', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{api.path}</div>
                              {api.description && <div style={{ fontSize: 12, color: '#9ca3af', marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{api.description}</div>}
                            </div>
                          </div>
                        ))
                      )}
                    </div>
                  )}
                </div>

                {/* Trigger */}
                <div style={{ marginBottom: 24 }}>
                  <div style={styles.sectionTitle}>Trigger</div>
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
                    {TRIGGER_TYPES.map(trigger => (
                      <div key={trigger.id} onClick={() => setCurrentBinding(prev => ({ ...prev, trigger }))} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '12px 8px', backgroundColor: '#374151', borderRadius: 8, cursor: 'pointer', border: currentBinding.trigger?.id === trigger.id ? '2px solid #6366f1' : '2px solid transparent' }} title={trigger.description}>
                        <span style={{ fontSize: 20, marginBottom: 4 }}>{trigger.icon}</span>
                        <span style={{ fontSize: 11, fontWeight: 500, textAlign: 'center' }}>{trigger.label}</span>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Success Handler */}
                <div style={{ marginBottom: 24 }}>
                  <div style={styles.sectionTitle}>On Success</div>
                  <select style={{ ...styles.select, marginBottom: 12 }} value={currentBinding.successHandler?.type.id || 'toast'} onChange={(e) => { const type = HANDLER_TYPES.find(h => h.id === e.target.value)!; setCurrentBinding(prev => ({ ...prev, successHandler: { ...prev.successHandler!, type } })); }}>
                    {HANDLER_TYPES.map(h => <option key={h.id} value={h.id}>{h.label}</option>)}
                  </select>
                  {currentBinding.successHandler?.type.id !== 'none' && <input style={styles.input} placeholder="Success message" value={currentBinding.successHandler?.message || ''} onChange={(e) => setCurrentBinding(prev => ({ ...prev, successHandler: { ...prev.successHandler!, message: e.target.value } }))} />}
                  {currentBinding.successHandler?.type.id === 'redirect' && <input style={{ ...styles.input, marginTop: 8 }} placeholder="Redirect path (e.g., /dashboard)" value={currentBinding.successHandler?.redirectPath || ''} onChange={(e) => setCurrentBinding(prev => ({ ...prev, successHandler: { ...prev.successHandler!, redirectPath: e.target.value } }))} />}
                </div>

                {/* Error Handlers */}
                <div style={{ marginBottom: 24 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
                    <div style={styles.sectionTitle}>On Error</div>
                    <button style={{ ...styles.button, padding: '4px 12px', backgroundColor: '#4b5563', fontSize: 12 }} onClick={addErrorHandler}>+ Add Case</button>
                  </div>
                  {currentBinding.errorHandlers?.map((handler, idx) => (
                    <div key={handler.id} style={{ backgroundColor: '#2d3748', borderRadius: 8, padding: 12, marginBottom: 8 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
                        <span style={{ fontSize: 12, color: '#9ca3af' }}>Case #{idx + 1}</span>
                        {(currentBinding.errorHandlers?.length || 0) > 1 && <button style={{ background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer', fontSize: 16, padding: 0 }} onClick={() => removeErrorHandler(handler.id)}>✕</button>}
                      </div>
                      <div style={{ display: 'flex', gap: 8, marginBottom: 8 }}>
                        <select style={{ ...styles.select, flex: 2 }} value={handler.type.id} onChange={(e) => updateErrorHandler(handler.id, 'type', HANDLER_TYPES.find(h => h.id === e.target.value))}>
                          {HANDLER_TYPES.map(h => <option key={h.id} value={h.id}>{h.label}</option>)}
                        </select>
                        <input style={{ ...styles.input, flex: 1 }} placeholder="Error code" value={handler.errorCode || ''} onChange={(e) => updateErrorHandler(handler.id, 'errorCode', e.target.value)} title="Optional: Business error code" />
                      </div>
                      {handler.type.id !== 'none' && <input style={styles.input} placeholder="Error message" value={handler.message || ''} onChange={(e) => updateErrorHandler(handler.id, 'message', e.target.value)} />}
                      {handler.type.id === 'redirect' && <input style={{ ...styles.input, marginTop: 8 }} placeholder="Redirect path" value={handler.redirectPath || ''} onChange={(e) => updateErrorHandler(handler.id, 'redirectPath', e.target.value)} />}
                    </div>
                  ))}
                </div>

                {/* Actions */}
                <div style={{ display: 'flex', gap: 12 }}>
                  <button style={{ ...styles.button, backgroundColor: '#6366f1', color: 'white', flex: 1, opacity: currentBinding.api ? 1 : 0.5 }} disabled={!currentBinding.api} onClick={completeBinding}>Add Binding</button>
                  <button style={{ ...styles.button, backgroundColor: '#374151', color: 'white' }} onClick={() => setPanelStep('mode')}>Back</button>
                  <button style={{ ...styles.button, backgroundColor: '#374151', color: 'white' }} onClick={() => resetPanel(false)}>Cancel</button>
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export default PromptInspector;
