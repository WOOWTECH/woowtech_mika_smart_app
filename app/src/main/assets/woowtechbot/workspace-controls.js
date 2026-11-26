/* Preview 06 host controls. No cookie/storage/content reads, network calls, or native JS interface. */
(function (config) {
  const root = document.documentElement;
  const existing = window.__woowWorkspaceAppearance;
  if (existing) { existing(config.skin); return !!document.querySelector('[data-look="app"]'); }
  function appearance(skin) {
    root.dataset.skin = skin;
    root.style.colorScheme = skin === 'midnight' ? 'dark' : 'light';
  }
  window.__woowWorkspaceAppearance = appearance;
  appearance(config.skin);
  const style = document.createElement('style');
  style.textContent = `
    [data-sidebar-top-slot]:has(>.woow-workspace-controls){gap:8px}
    .woow-workspace-controls{display:flex;flex:1;align-items:center;justify-content:space-between;gap:8px;padding:0 12px;min-width:0;pointer-events:auto;-webkit-app-region:no-drag}
    .woow-workspace-controls a{display:flex;align-items:center;justify-content:center;flex-shrink:0;width:40px;height:40px;border-radius:50%;border:1px solid var(--color-hairline);background:var(--color-card);color:var(--color-ink);text-decoration:none}
    .woow-workspace-controls a:focus-visible{outline:2px solid var(--color-accent,#7fc0ff);outline-offset:3px}
    .woow-workspace-controls svg{width:20px;height:20px;fill:none;stroke:currentColor;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}
    @media(min-width:768px){.woow-workspace-controls{padding:0;gap:5px;justify-content:flex-end}.woow-workspace-controls a{width:36px;height:36px}}
  `;
  document.head.append(style);
  const glyphs = {
    services: '<path d="M4 7h16m-4-4 4 4-4 4M20 17H4m4-4-4 4 4 4"/>',
    notifications: '<path d="M5 9a7 7 0 0 1 14 0c0 7 2 7 2 9H3c0-2 2-2 2-9M10 22h4"/>'
  };
  function attach() {
    for (const slot of document.querySelectorAll('[data-sidebar-top-slot]')) {
      if (slot.querySelector('.woow-workspace-controls')) continue;
      const controls = document.createElement('div'); controls.className = 'woow-workspace-controls';
      for (const action of ['services', 'notifications']) {
        const button = document.createElement('a');
        button.href = 'woowtech-ui://' + action;
        button.setAttribute('role', 'button');
        button.setAttribute('aria-label', config[action]);
        button.setAttribute('aria-haspopup', 'dialog');
        button.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">' + glyphs[action] + '</svg>';
        controls.append(button);
      }
      slot.prepend(controls);
    }
  }
  let queued = false;
  new MutationObserver(() => {
    if (!queued) { queued = true; requestAnimationFrame(() => { queued = false; attach(); }); }
  }).observe(root, {childList:true, subtree:true});
  attach();
  return !!document.querySelector('[data-look="app"]');
})(__WOOW_CONFIGURATION__)
