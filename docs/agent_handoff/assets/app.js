/*
 * Auto Folo Wiki — 页面运行时
 * 经典 script：加载后渲染导航、Markdown 正文、目录、搜索与主题切换。
 * 不依赖 ES Module、fetch、Service Worker 或任何网络资源，file:// 下可用。
 */
(function () {
  'use strict';

  document.documentElement.classList.add('js');

  function $(sel) { return document.querySelector(sel); }
  function meta(name) {
    var el = document.querySelector('meta[name="' + name + '"]');
    return el ? el.getAttribute('content') : '';
  }

  var wikiBase = meta('wiki-base') || '.';
  var repoRoot = meta('repo-root') || '.';
  var contentEl = $('#wiki-content');
  var renderEl = $('#wiki-rendered');

  /* ── 导航 ─────────────────────────────────────── */

  function currentPagePath() {
    var pathname = location.pathname;
    var base = pathname.split('/').filter(Boolean).pop() || 'index.html';
    var wikiPath = pathname.split('/docs/agent_handoff/');
    return wikiPath.length === 2 ? wikiPath[1] : 'index.html';
  }

  function renderNav() {
    var nav = $('#wiki-nav');
    if (!nav || typeof window.WIKI_NAV === 'undefined') return;
    var current = currentPagePath();
    window.WIKI_NAV.forEach(function (group) {
      var g = document.createElement('div');
      g.className = 'nav-group';
      var title = document.createElement('div');
      title.className = 'nav-group-title';
      title.textContent = group.group;
      g.appendChild(title);
      group.items.forEach(function (item) {
        var a = document.createElement('a');
        a.className = 'nav-item' + (item.sub ? ' nav-sub' : '');
        a.href = (item.home ? repoRoot + '/' : wikiBase + '/') + item.path;
        a.textContent = item.title;
        if (item.path === current) {
          a.classList.add('nav-current');
          a.setAttribute('aria-current', 'page');
        }
        g.appendChild(a);
      });
      nav.appendChild(g);
    });
  }

  /* ── Markdown 渲染 ────────────────────────────── */

  function renderContent() {
    if (!contentEl || !renderEl || typeof window.markdownit === 'undefined') return;
    var raw = window.WikiCommon.unescapeScriptClose(contentEl.textContent);
    var md = window.markdownit({
      html: true,
      linkify: false,
      typographer: false,
    });
    if (typeof window.markdownItAnchor !== 'undefined') {
      md.use(window.markdownItAnchor, { slugify: window.WikiCommon.slugify });
    }
    renderEl.innerHTML = md.render(raw);

    // 文档标题进入 <title>
    var h1 = renderEl.querySelector('h1');
    if (h1) {
      document.title = h1.textContent + ' · Auto Folo Wiki';
    }
  }

  /* ── 目录（本页锚点）──────────────────────────── */

  function renderToc() {
    var toc = $('#wiki-toc');
    if (!toc || !renderEl) return;
    var headings = renderEl.querySelectorAll('h2, h3');
    if (!headings.length) { toc.innerHTML = ''; return; }
    var title = document.createElement('div');
    title.className = 'toc-title';
    title.textContent = '本页目录';
    toc.appendChild(title);
    headings.forEach(function (h) {
      if (!h.id) return;
      var a = document.createElement('a');
      a.href = '#' + h.id;
      a.textContent = h.textContent;
      if (h.tagName === 'H3') a.classList.add('toc-h3');
      a.addEventListener('click', function () { setActiveToc(a); });
      toc.appendChild(a);
    });

    var links = toc.querySelectorAll('a');
    function setActiveToc(a) {
      links.forEach(function (l) { l.classList.remove('toc-current'); });
      if (a) a.classList.add('toc-current');
    }
    var positions = [];
    headings.forEach(function (h, i) { positions.push({ el: h, link: links[i] }); });
    function onScroll() {
      var mark = null;
      var pos = window.scrollY + 90;
      for (var i = 0; i < positions.length; i++) {
        if (positions[i].el.getBoundingClientRect().top + window.scrollY <= pos) mark = positions[i];
        else break;
      }
      if (mark && mark.link) setActiveToc(mark.link);
    }
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
  }

  /* ── 主题 ─────────────────────────────────────── */

  var THEME_KEY = 'wiki-theme';

  function systemDark() {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  function readTheme() {
    try {
      var v = localStorage.getItem(THEME_KEY);
      if (v === 'light' || v === 'dark' || v === 'auto') return v;
    } catch (e) { /* file:// 下 Safari 可能禁止存储，降级为 auto */ }
    return 'auto';
  }

  function applyTheme(t) {
    var resolved = t === 'auto' ? (systemDark() ? 'dark' : 'light') : t;
    document.documentElement.setAttribute('data-theme', resolved);
    try { localStorage.setItem(THEME_KEY, t); } catch (e) { /* 忽略 */ }
    var sun = $('.theme-icon-sun'), moon = $('.theme-icon-moon'), auto = $('.theme-icon-auto');
    if (sun) sun.style.display = t === 'light' ? '' : 'none';
    if (moon) moon.style.display = t === 'dark' ? '' : 'none';
    if (auto) auto.style.display = t === 'auto' ? '' : 'none';
  }

  function initTheme() {
    var btn = $('#theme-toggle');
    if (!btn) return;
    applyTheme(readTheme());
    btn.addEventListener('click', function (e) {
      var order = ['auto', 'light', 'dark'];
      var next = order[(order.indexOf(readTheme()) + 1) % order.length];
      btn.classList.add('icons-swap');
      setTimeout(function () { btn.classList.remove('icons-swap'); }, 220);
      var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      if (!reduced && document.startViewTransition) {
        var rect = btn.getBoundingClientRect();
        document.documentElement.style.setProperty('--vt-x', Math.round(rect.left + rect.width / 2) + 'px');
        document.documentElement.style.setProperty('--vt-y', Math.round(rect.top + rect.height / 2) + 'px');
        document.startViewTransition(function () { applyTheme(next); });
      } else {
        applyTheme(next);
      }
    });
    // 跟随系统主题变化（仅 auto 模式）
    if (window.matchMedia) {
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () {
        if (readTheme() === 'auto') applyTheme('auto');
      });
    }
  }

  /* ── 缓动库（移植自 huashu-design animations.jsx）── */

  var EASING = {
    expoOut: function (t) { return t === 1 ? 1 : 1 - Math.pow(2, -10 * t); },
    overshoot: function (t) {
      var c1 = 1.70158, c3 = c1 + 1;
      return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
    },
    anticipation: function (t) {
      if (t < 0.2) return -0.3 * (t / 0.2) * (t / 0.2);
      var a = (t - 0.2) / 0.8;
      return -0.012 + 1.012 * a * a * (3 - 2 * a);
    },
    easeOutCubic: function (t) { return 1 - Math.pow(1 - t, 3); },
  };

  /* ── 搜索与命令面板共用工具 ───────────────────── */

  function norm(s) { return (s || '').toLowerCase(); }

  // 轻量模糊匹配（CJK 友好，无第三方依赖）：
  // 精确包含得满分；否则拆成英文词 + 单个汉字，要求全部命中并按顺序性加权
  function fuzzyScore(text, q) {
    var tl = norm(text);
    if (tl.indexOf(q) !== -1) return 1;
    var toks = [];
    (q.match(/[a-z0-9]+/gi) || []).forEach(function (w) { toks.push(w.toLowerCase()); });
    (q.match(/[\u4e00-\u9fff]/g) || []).forEach(function (c) { toks.push(c); });
    if (!toks.length) return 0;
    var hit = 0, last = -1, ordered = true;
    for (var i = 0; i < toks.length; i++) {
      var idx = tl.indexOf(toks[i]);
      if (idx === -1) { ordered = false; continue; }
      if (idx < last) ordered = false;
      last = idx;
      hit++;
    }
    if (!hit) return 0;
    var cov = hit / toks.length;
    return ordered ? 0.5 * cov + 0.4 : 0.3 * cov;
  }

  /* ── 搜索 ─────────────────────────────────────── */

  function initSearch() {
    var input = $('#wiki-search-input');
    var panel = $('#search-results');
    if (!input || !panel) return;
    var index = (typeof window.WIKI_SEARCH_INDEX !== 'undefined') ? window.WIKI_SEARCH_INDEX : [];
    var active = -1;
    var items = [];

    function score(entry, q) {
      var s = 0;
      s += 100 * fuzzyScore(entry.title, q);
      entry.headings.forEach(function (h) { s += 30 * fuzzyScore(h.text, q); });
      s += 10 * fuzzyScore(entry.text, q);
      return s;
    }

    function snippet(entry, q) {
      var ql = norm(q);
      var t = norm(entry.text);
      var i = t.indexOf(ql);
      if (i === -1) return '';
      var start = Math.max(0, i - 30);
      var end = Math.min(entry.text.length, i + q.length + 60);
      return (start > 0 ? '…' : '') + entry.text.slice(start, end) + (end < entry.text.length ? '…' : '');
    }

    function show() {
      var ir = input.getBoundingClientRect();
      var pw = Math.min(720, window.innerWidth - 24);
      var originX = Math.max(0, Math.min(pw, ir.left + ir.width / 2 - (window.innerWidth - pw) / 2));
      panel.style.transformOrigin = originX + 'px top';
      panel.classList.add('open');
    }

    function hide() {
      panel.classList.remove('open');
    }

    function render(q) {
      items = [];
      active = -1;
      panel.innerHTML = '';
      if (!q) { hide(); return; }
      var ranked = index
        .map(function (e) { return { e: e, s: score(e, q) }; })
        .filter(function (r) { return r.s > 0; })
        .sort(function (a, b) { return b.s - a.s; })
        .slice(0, 20);
      if (!ranked.length) {
        var empty = document.createElement('div');
        empty.className = 'sr-empty';
        empty.textContent = '没有找到匹配的文档';
        panel.appendChild(empty);
      }
      ranked.forEach(function (r) {
        var a = document.createElement('a');
        a.href = (r.e.home ? repoRoot + '/' : wikiBase + '/') + r.e.path;
        var t = document.createElement('div');
        t.className = 'sr-title';
        t.textContent = r.e.title;
        var p = document.createElement('span');
        p.className = 'sr-path';
        p.textContent = r.e.path;
        t.appendChild(p);
        a.appendChild(t);
        var sn = snippet(r.e, q);
        if (sn) {
          var s = document.createElement('div');
          s.className = 'sr-snippet';
          s.textContent = sn;
          a.appendChild(s);
        }
        a.addEventListener('mouseenter', function () { setActive(items.indexOf(a)); });
        items.push(a);
        panel.appendChild(a);
      });
      show();
    }

    function setActive(i) {
      if (i < 0 || i >= items.length) return;
      if (active >= 0 && items[active]) items[active].classList.remove('sr-active');
      active = i;
      items[active].classList.add('sr-active');
      if (items[active].scrollIntoView) items[active].scrollIntoView({ block: 'nearest' });
    }

    input.addEventListener('input', function () { render(input.value.trim()); });
    input.addEventListener('keydown', function (e) {
      if (!items.length) return;
      if (e.key === 'ArrowDown') { e.preventDefault(); setActive((active + 1) % items.length); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); setActive((active - 1 + items.length) % items.length); }
      else if (e.key === 'Enter') { if (active >= 0) { e.preventDefault(); location.href = items[active].href; } }
      else if (e.key === 'Escape') { hide(); input.blur(); }
    });
    input.addEventListener('blur', function () {
      setTimeout(hide, 150);
    });
    input.addEventListener('focus', function () { if (input.value.trim()) render(input.value.trim()); });
  }

  /* ── 移动端导航开关 ───────────────────────────── */

  function initNavToggle() {
    var btn = $('.nav-toggle');
    var nav = $('#wiki-nav');
    if (!btn || !nav) return;
    btn.addEventListener('click', function () { nav.classList.toggle('nav-open'); });
    nav.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') nav.classList.remove('nav-open');
    });
  }

  /* ── 每页视觉横幅 ─────────────────────────────── */

  var SECTION_META = {
    status:   { label: '状态',   icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>' },
    product:  { label: '产品',   icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/></svg>' },
    arch:     { label: '架构',   icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/><path d="M3 17l9 5 9-5"/></svg>' },
    feature:  { label: '功能',   icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l2.2 5.6L20 11l-5.8 2.4L12 19l-2.2-5.6L4 11l5.8-2.4z"/><path d="M19 16.5l.9 2.1 2.1.9-2.1.9-.9 2.1-.9-2.1-2.1-.9 2.1-.9z"/></svg>' },
    platform: { label: '平台',   icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8M12 17v4"/></svg>' },
    design:   { label: '设计',   icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 0 0 18c1.5 0 2-1 2-2s-1-1.5-1-2.5c0-1 .8-2.5 2.5-2.5H19a8 8 0 0 0-7-11z"/></svg>' },
    ops:      { label: '操作',   icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 17l6-6-6-6M12 19h8"/></svg>' },
    history:  { label: '历史',   icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/></svg>' },
    archive:  { label: '历史归档', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8"/><path d="M10 12h4"/></svg>' },
    legal:    { label: '许可',   icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l8 4-8 4-8-4z"/><path d="M4 11l8 4 8-4"/><path d="M4 15l8 4 8-4"/></svg>' },
    meta:     { label: '关于',   icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 8h.01M11 12h1v4h1"/></svg>' },
  };

  function sectionOf() {
    var p = currentPagePath();
    if (p.indexOf('history/archive/') === 0) return 'archive';
    var SEC_DIR = {
      status: 'status', product: 'product', architecture: 'arch',
      features: 'feature', platforms: 'platform', design: 'design',
      operations: 'ops', history: 'history', legal: 'legal', meta: 'meta',
    };
    var key = p.split('/')[0];
    return SEC_DIR[key] || 'meta';
  }

  function buildPageBanner() {
    if (document.body.classList.contains('wiki-full') || !renderEl) return;
    var h1 = renderEl.querySelector('h1');
    if (!h1) return;
    var sec = sectionOf();
    var meta = SECTION_META[sec] || SECTION_META.meta;
    var sub = '';
    var firstP = renderEl.querySelector('p');
    if (firstP && firstP.textContent.trim().length > 6) {
      sub = firstP.textContent.trim();
    }
    var banner = document.createElement('div');
    banner.className = 'page-banner banner-sec-' + sec;
    banner.innerHTML =
      '<div class="banner-icon">' + meta.icon + '</div>' +
      '<div class="banner-text"></div>' +
      '<span class="banner-rule">' + meta.label + '</span>' +
      '<span class="banner-chip">约 ' + readMinutes() + ' 分钟</span>';
    var id = h1.id;
    var titleEl = document.createElement('h1');
    if (id) titleEl.id = id;
    titleEl.textContent = h1.textContent;
    banner.querySelector('.banner-text').appendChild(titleEl);
    if (sub) {
      var p = document.createElement('p');
      p.className = 'banner-sub';
      p.textContent = sub;
      banner.querySelector('.banner-text').appendChild(p);
    }
    renderEl.insertBefore(banner, renderEl.firstChild);
    h1.remove();
    if (firstP && firstP.parentNode === renderEl) {
      var h2 = renderEl.querySelector('h2');
      var idxP = Array.prototype.indexOf.call(renderEl.children, firstP);
      var idxH2 = h2 ? Array.prototype.indexOf.call(renderEl.children, h2) : renderEl.children.length;
      if (idxP >= 0 && idxP < idxH2) firstP.remove();
    }
  }

  // 阅读时长估算：中文按 350 字/分钟、英文按 180 词/分钟
  function readMinutes() {
    if (!renderEl) return 1;
    var t = renderEl.textContent || '';
    var cjk = (t.match(/[\u4e00-\u9fff]/g) || []).length;
    var latin = (t.match(/[A-Za-z0-9]+/g) || []).length;
    return Math.max(1, Math.round(cjk / 350 + latin / 180));
  }

  /* ── 阅读进度条 ───────────────────────────────── */

  function initProgress() {
    var bar = document.createElement('div');
    bar.className = 'wiki-progress';
    document.body.appendChild(bar);
    var ticking = false;
    function update() {
      ticking = false;
      var doc = document.documentElement;
      var max = doc.scrollHeight - doc.clientHeight;
      bar.style.width = (max > 0 ? (window.scrollY / max) * 100 : 0) + '%';
    }
    window.addEventListener('scroll', function () {
      if (!ticking) { ticking = true; requestAnimationFrame(update); }
    }, { passive: true });
    update();
  }

  /* ── 代码块复制按钮 ───────────────────────────── */

  function initCopyButtons() {
    if (!renderEl) return;
    renderEl.querySelectorAll('pre').forEach(function (pre) {
      if (pre.querySelector('.pre-copy')) return;
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'pre-copy';
      btn.textContent = '复制';
      var CK = '<svg class="ck-svg" width="11" height="11" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path class="ck-path" d="M2 6.5 5 9.5 10 3"/></svg>';
      btn.addEventListener('click', function () {
        var code = pre.querySelector('code');
        var text = code ? code.textContent : pre.textContent;
        var done = function () {
          btn.innerHTML = CK + '已复制';
          btn.classList.add('copied');
          setTimeout(function () {
            btn.textContent = '复制';
            btn.classList.remove('copied');
          }, 1500);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, function () { fallbackCopy(text); done(); });
        } else {
          fallbackCopy(text);
          done();
        }
      });
      pre.appendChild(btn);
    });
    function fallbackCopy(text) {
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); } catch (e) { }
      ta.remove();
    }
  }

  /* ── 图形灯箱 ─────────────────────────────────── */

  function initLightbox() {
    if (!renderEl) return;
    var dlg = document.createElement('dialog');
    dlg.id = 'dg-lightbox';
    dlg.setAttribute('aria-label', '图形放大查看');
    document.body.appendChild(dlg);
    dlg.addEventListener('click', function (e) {
      if (e.target === dlg) dlg.close();
    });
    renderEl.addEventListener('click', function (e) {
      var svg = e.target.closest ? e.target.closest('.dg svg') : null;
      if (!svg) return;
      var frame = document.createElement('div');
      frame.className = 'lb-frame';
      var clone = svg.cloneNode(true);
      // 按视口与图形宽高比计算灯箱宽度，保证任意比例下都大于内嵌图且不溢出
      var ratio = 2;
      var vb = svg.getAttribute('viewBox');
      if (vb) {
        var p = vb.trim().split(/[\s,]+/).map(Number);
        if (p.length === 4 && p[2] > 0 && p[3] > 0) ratio = p[2] / p[3];
      }
      // 视口宽度以布局视口为准（移动端 visual viewport 可能小于布局视口）
      var vw = document.documentElement.clientWidth || window.innerWidth;
      var vh = window.innerHeight || document.documentElement.clientHeight;
      var lw = Math.min(vw * 0.94, vh * 0.88 * ratio);
      // 宽度直接作用于 SVG（frame 为 fit-content，避免 box-sizing 吃掉 padding）
      clone.style.width = Math.max(320, Math.round(lw)) + 'px';
      frame.appendChild(clone);
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'lb-close';
      btn.textContent = '关闭（Esc）';
      btn.addEventListener('click', function () { dlg.close(); });
      frame.appendChild(btn);
      dlg.innerHTML = '';
      dlg.appendChild(frame);
      if (typeof dlg.showModal === 'function') dlg.showModal();
    });
  }

  /* ── 章节滚动渐显 ─────────────────────────────── */

  function initSectionReveal() {
    if (!renderEl || document.body.classList.contains('wiki-full')) return;
    if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    var heads = renderEl.querySelectorAll('h2, h3');
    if (heads.length < 3 || !('IntersectionObserver' in window)) return;
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add('revealed'); io.unobserve(en.target); }
      });
    }, { threshold: 0.05 });
    heads.forEach(function (h, i) {
      if (i < 2) return;
      h.classList.add('sec-reveal');
      io.observe(h);
    });
  }

  /* ── 命令面板（Ctrl+K / ?）────────────────────── */

  var CMD_ACTIONS = null;

  function cmdPaletteEls() {
    var dlg = $('#cmd-palette');
    if (dlg) return { dlg: dlg, input: $('#cmd-input'), list: $('#cmd-results') };
    dlg = document.createElement('dialog');
    dlg.id = 'cmd-palette';
    dlg.setAttribute('aria-label', '命令面板');
    dlg.innerHTML =
      '<input id="cmd-input" type="text" placeholder="搜索页面或输入命令…" autocomplete="off" aria-label="命令面板搜索">' +
      '<div id="cmd-results"></div>';
    document.body.appendChild(dlg);
    return { dlg: dlg, input: $('#cmd-input'), list: $('#cmd-results') };
  }

  function buildCmdActions() {
    if (CMD_ACTIONS) return CMD_ACTIONS;
    var self = {
      theme: { title: '切换明暗主题', hint: '点击按钮', run: function () { var b = $('#theme-toggle'); if (b) b.click(); } },
      settings: { title: '阅读设置（字号/行距/宽度）', hint: '', run: function () { var b = $('.read-toggle'); if (b) b.click(); } },
      top: { title: '返回顶部', hint: 't', run: function () { window.scrollTo({ top: 0, behavior: (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) ? 'auto' : 'smooth' }); } },
      home: { title: '打开 Wiki 首页', hint: '', run: function () { location.href = repoRoot + '/index.html'; } },
      help: { title: '快捷键帮助', hint: '?', run: function () { renderCmdHelp(); } },
    };
    CMD_ACTIONS = [self.theme, self.settings, self.top, self.home, self.help];
    return CMD_ACTIONS;
  }

  var HELP_ROWS = [
    ['Cmd / Ctrl + K', '打开命令面板'],
    ['/ ', '聚焦搜索'],
    ['?', '快捷键帮助'],
    ['n / p', '下一页 / 上一页'],
    ['t', '返回顶部'],
    ['Esc', '关闭浮层'],
  ];

  function renderCmdHelp() {
    var els = cmdPaletteEls();
    var h = '<div class="cmd-help">';
    HELP_ROWS.forEach(function (r) {
      h += '<div class="ch-row"><span>' + r[1] + '</span><kbd>' + r[0] + '</kbd></div>';
    });
    h += '</div>';
    els.list.innerHTML = h;
  }

  function renderCmd(query) {
    var els = cmdPaletteEls();
    var q = norm(query);
    var html = '';
    var actions = buildCmdActions().filter(function (a) {
      return !q || fuzzyScore(a.title, q) > 0;
    });
    if (actions.length) {
      html += '<div class="cmd-group">动作</div>';
      actions.forEach(function (a, i) {
        html += '<div class="cmd-item" data-act="' + i + '" tabindex="0">' + a.title +
          (a.hint ? '<span class="cmd-key">' + a.hint + '</span>' : '') + '</div>';
      });
    }
    var index = (typeof window.WIKI_SEARCH_INDEX !== 'undefined') ? window.WIKI_SEARCH_INDEX : [];
    var pages = index
      .map(function (e) { return { e: e, s: scoreEntry(e, q) }; })
      .filter(function (r) { return r.s > 0; })
      .sort(function (a, b) { return b.s - a.s; })
      .slice(0, 12);
    if (pages.length) {
      html += '<div class="cmd-group">页面</div>';
      pages.forEach(function (r) {
        html += '<a href="' + (r.e.home ? repoRoot + '/' : wikiBase + '/') + r.e.path + '">' +
          r.e.title + '<span class="cmd-path">' + r.e.path + '</span></a>';
      });
    }
    if (!actions.length && !pages.length) {
      html = '<div class="cmd-empty">没有匹配的页面或命令</div>';
    }
    els.list.innerHTML = html;
    els.list.querySelectorAll('.cmd-item').forEach(function (el) {
      el.addEventListener('click', function () {
        var act = buildCmdActions()[Number(el.getAttribute('data-act'))];
        if (act) { els.dlg.close(); act.run(); }
      });
    });
    els.list.querySelectorAll('a, .cmd-item').forEach(function (el, i) {
      el.addEventListener('mouseenter', function () { setCmdActive(i); });
    });
  }

  function scoreEntry(entry, q) {
    var s = 0;
    s += 100 * fuzzyScore(entry.title, q);
    entry.headings.forEach(function (h) { s += 30 * fuzzyScore(h.text, q); });
    s += 10 * fuzzyScore(entry.text, q);
    return s;
  }

  var cmdActiveIdx = -1;
  var cmdItems = [];

  function setCmdActive(i) {
    var els = cmdPaletteEls();
    var items = els.list.querySelectorAll('a, .cmd-item');
    if (i < 0 || i >= items.length) return;
    if (cmdActiveIdx >= 0 && items[cmdActiveIdx]) items[cmdActiveIdx].classList.remove('cmd-active');
    cmdActiveIdx = i;
    items[cmdActiveIdx].classList.add('cmd-active');
    if (items[cmdActiveIdx].scrollIntoView) items[cmdActiveIdx].scrollIntoView({ block: 'nearest' });
  }

  function openCmdPalette(helpMode) {
    var els = cmdPaletteEls();
    if (!els.dlg.open) els.dlg.showModal();
    if (helpMode) {
      renderCmdHelp();
      els.input.blur();
    } else {
      els.input.value = '';
      renderCmd('');
      els.input.focus();
    }
  }

  function initCommandPalette() {
    var els = cmdPaletteEls();
    els.input.addEventListener('input', function () { renderCmd(els.input.value); });
    els.input.addEventListener('keydown', function (e) {
      var items = els.list.querySelectorAll('a, .cmd-item');
      if (!items.length) return;
      if (e.key === 'ArrowDown') { e.preventDefault(); setCmdActive((cmdActiveIdx + 1) % items.length); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); setCmdActive((cmdActiveIdx - 1 + items.length) % items.length); }
      else if (e.key === 'Enter') {
        e.preventDefault();
        if (cmdActiveIdx >= 0 && items[cmdActiveIdx]) items[cmdActiveIdx].click();
      }
    });
    els.list.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter') {
        e.preventDefault();
        els.input.focus();
      }
    });
  }

  /* ── 阅读设置（Tweaks）────────────────────────── */

  var READ_KEY = 'wiki-read';

  function readSettings() {
    try {
      var v = JSON.parse(localStorage.getItem(READ_KEY));
      if (v && typeof v === 'object') return v;
    } catch (e) { /* 忽略 */ }
    return { scale: '1', lh: '1.75', width: '100%', motion: 'on' };
  }

  function applySettings(s) {
    document.documentElement.style.setProperty('--read-scale', s.scale);
    document.documentElement.style.setProperty('--read-lh', s.lh);
    document.documentElement.style.setProperty('--read-width', s.width);
    document.documentElement.classList.toggle('no-anim', s.motion !== 'on');
    try { localStorage.setItem(READ_KEY, JSON.stringify(s)); } catch (e) { /* 忽略 */ }
    var dlg = $('#read-settings');
    if (dlg) {
      dlg.querySelectorAll('.rs-seg').forEach(function (seg) {
        seg.querySelectorAll('button').forEach(function (b) {
          b.classList.toggle('active', b.getAttribute('data-v') === String(s[b.getAttribute('data-k')]));
        });
      });
    }
  }

  function initReadSettings() {
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'read-toggle';
    btn.textContent = 'Aa';
    btn.setAttribute('aria-label', '阅读设置');
    btn.title = '阅读设置（字号 / 行距 / 宽度 / 动效）';
    document.body.appendChild(btn);

    var dlg = document.createElement('dialog');
    dlg.id = 'read-settings';
    dlg.setAttribute('aria-label', '阅读设置');
    dlg.innerHTML =
      '<h3>阅读设置</h3>' +
      '<div class="rs-row"><span class="rs-label">字号</span><div class="rs-seg" data-k="scale">' +
      '<button data-v="0.9">小</button><button data-v="1">标准</button><button data-v="1.15">大</button><button data-v="1.3">特大</button></div></div>' +
      '<div class="rs-row"><span class="rs-label">行距</span><div class="rs-seg" data-k="lh">' +
      '<button data-v="1.6">紧凑</button><button data-v="1.75">标准</button><button data-v="2">宽松</button></div></div>' +
      '<div class="rs-row"><span class="rs-label">正文宽度</span><div class="rs-seg" data-k="width">' +
      '<button data-v="100%">标准</button><button data-v="46rem">窄</button></div></div>' +
      '<div class="rs-row"><span class="rs-label">动效</span><div class="rs-seg" data-k="motion">' +
      '<button data-v="on">开</button><button data-v="off">关</button></div></div>';
    document.body.appendChild(dlg);

    btn.addEventListener('click', function () {
      if (dlg.open) dlg.close();
      else dlg.showModal();
    });

    dlg.addEventListener('click', function (e) {
      var b = e.target.closest('.rs-seg button');
      if (!b) return;
      var seg = b.parentElement;
      var s = readSettings();
      s[seg.getAttribute('data-k')] = b.getAttribute('data-v');
      applySettings(s);
    });

    applySettings(readSettings());
  }

  /* ── 键盘导航 ─────────────────────────────────── */

  function isEditableTarget(e) {
    var t = e.target;
    return !!(t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable));
  }

  function flatNav() {
    var out = [];
    if (typeof window.WIKI_NAV !== 'undefined') {
      window.WIKI_NAV.forEach(function (g) {
        g.items.forEach(function (it) { out.push(it); });
      });
    }
    return out;
  }

  function navAdj(delta) {
    var flat = flatNav();
    if (!flat.length) return;
    var cur = currentPagePath();
    var idx = -1;
    for (var i = 0; i < flat.length; i++) {
      if (flat[i].path === cur) { idx = i; break; }
    }
    if (idx === -1) idx = 0;
    var next = flat[(idx + delta + flat.length) % flat.length];
    location.href = (next.home ? repoRoot + '/' : wikiBase + '/') + next.path;
  }

  function initKeyboardNav() {
    document.addEventListener('keydown', function (e) {
      if (e.isComposing || e.keyCode === 229) return;
      if ((e.metaKey || e.ctrlKey) && (e.key === 'k' || e.key === 'K')) {
        e.preventDefault();
        openCmdPalette(false);
        return;
      }
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      if (isEditableTarget(e)) return;
      switch (e.key) {
        case '/':
          e.preventDefault();
          var si = $('#wiki-search-input');
          if (si) si.focus();
          break;
        case '?':
          e.preventDefault();
          openCmdPalette(true);
          break;
        case 'n': case 'N':
          e.preventDefault();
          navAdj(1);
          break;
        case 'p': case 'P':
          e.preventDefault();
          navAdj(-1);
          break;
        case 't': case 'T':
          e.preventDefault();
          window.scrollTo({ top: 0, behavior: (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) ? 'auto' : 'smooth' });
          break;
      }
    });
  }

  /* ── mockup 流程演示（huashu Dashboard+Cinematic 模式）── */

  function initMockupCinematic() {
    if (!renderEl) return;
    var playBtn = renderEl.querySelector('.mock-play');
    if (!playBtn) return;
    var win = playBtn.closest('.mock-window');
    var list = win.querySelector('.mock-list');
    var article = win.querySelector('.mock-article');
    var running = false;
    var html = document.documentElement;

    function buildCard() {
      var proto = list.querySelector('.mock-card');
      var card = proto ? proto.cloneNode(true) : document.createElement('div');
      card.className = 'mock-card enter from';
      card.classList.remove('read', 'flagged');
      return card;
    }

    function addBar() {
      var b = document.createElement('div');
      b.className = 'ma-para grow';
      article.appendChild(b);
      requestAnimationFrame(function () {
        requestAnimationFrame(function () { b.classList.add('on'); });
      });
    }

    function reset() {
      var temp = list.querySelector('.mock-card.enter');
      if (temp) temp.remove();
      article.querySelectorAll('.ma-para.grow').forEach(function (b) { b.remove(); });
      win.classList.remove('playing');
      running = false;
    }

    playBtn.addEventListener('click', function () {
      if (running) return;
      running = true;
      win.classList.add('playing');
      var card = buildCard();
      list.insertBefore(card, list.firstChild);
      var reduced = reducedMotion() || html.classList.contains('no-anim');
      if (reduced) {
        // 减动效：直接显示终态，短暂停留后复位
        card.classList.remove('from');
        card.classList.add('flagged');
        addBar(); addBar();
        card.classList.add('read');
        setTimeout(reset, 1400);
        return;
      }
      // Scene 1 · 新卡片进入（0s）
      requestAnimationFrame(function () {
        requestAnimationFrame(function () { card.classList.remove('from'); });
      });
      // Scene 2 · AI 判定（1.6s）
      setTimeout(function () { card.classList.add('flagged'); }, 1600);
      // Scene 3 · 阅读填充（3.2s / 3.7s）
      setTimeout(function () { addBar(); }, 3200);
      setTimeout(function () { addBar(); }, 3600);
      // Scene 4 · 已读（6.0s）
      setTimeout(function () {
        card.classList.add('read');
      }, 6000);
      // Scene 5 · 复位（7.6s）
      setTimeout(reset, 7600);
    });
  }

  /* ── 落地页效果（Apple 式滚动叙事）────────────── */

  function reducedMotion() {
    return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }

  function initLandingFx() {
    if (!document.body.classList.contains('wiki-full')) return;
    var html = document.documentElement;
    var heroH2 = renderEl ? renderEl.querySelector('.hero h2') : null;

    // 1) hero 标题随滚动轻微缩放（退场感）
    if (heroH2 && !reducedMotion()) {
      var ticking = false;
      window.addEventListener('scroll', function () {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(function () {
          ticking = false;
          var y = window.scrollY;
          var scale = Math.max(0.86, 1 - y * 0.00028);
          var opacity = Math.max(0, 1 - y * 0.0011);
          heroH2.style.transform = 'scale(' + scale + ')';
          heroH2.style.opacity = opacity;
        });
      }, { passive: true });
    }

    // 2) 大数字滚动递增
    var counters = renderEl ? renderEl.querySelectorAll('.stat-num') : [];
    if (counters.length) {
      var setNum = function (el, v) {
        // 只更新首个文本节点，保留 % 等后缀子元素
        var tn = el.firstChild;
        if (tn && tn.nodeType === 3) tn.textContent = v;
        else el.textContent = v;
      };
      var animate = function (el) {
        var target = Number(el.getAttribute('data-count') || 0);
        var dur = 1200;
        var t0 = null;
        function step(ts) {
          if (!t0) t0 = ts;
          var p = Math.min(1, (ts - t0) / dur);
          setNum(el, Math.round(target * EASING.expoOut(p)));
          if (p < 1) requestAnimationFrame(step);
        }
        requestAnimationFrame(step);
      };
      var io = ('IntersectionObserver' in window) ? new IntersectionObserver(function (entries) {
        entries.forEach(function (en) {
          if (en.isIntersecting) { animate(en.target); io.unobserve(en.target); }
        });
      }, { threshold: 0.4 }) : null;
      counters.forEach(function (c) {
        if (reducedMotion() || html.classList.contains('no-anim')) {
          setNum(c, c.getAttribute('data-count'));
        } else if (io) {
          io.observe(c);
        } else {
          setNum(c, c.getAttribute('data-count'));
        }
      });
    }

    // 3) 展示区块模糊渐显（场景化：区块 blur-in + 行级 stagger）
    var reveals = renderEl ? renderEl.querySelectorAll('.hp-reveal') : [];
    if (reveals.length && !reducedMotion() && !html.classList.contains('no-anim') && 'IntersectionObserver' in window) {
      var rio = new IntersectionObserver(function (entries) {
        entries.forEach(function (en) {
          if (!en.isIntersecting) return;
          en.target.classList.add('revealed');
          // 行级 stagger：卡片按行列交错进入（expoOut）
          var items = en.target.querySelectorAll('.highlight-card, .flow-step, .stat, .entry-card');
          items.forEach(function (it, i) {
            it.classList.add('reveal-item');
            it.style.transitionDelay = (Math.floor(i / 3) * 90 + (i % 3) * 50) + 'ms';
            requestAnimationFrame(function () {
              it.classList.add('reveal-item-show');
            });
            // 过渡结束后清除 delay，避免影响 hover 反馈
            setTimeout(function () { it.style.transitionDelay = ''; }, 1600);
          });
          rio.unobserve(en.target);
        });
      // 场景钉住前触发：场景顶部接近视口顶部（内容即将进入钉住区）
      }, { rootMargin: '0px 0px -80% 0px', threshold: 0 });
      reveals.forEach(function (el, i) {
        el.style.transitionDelay = (i % 3) * 60 + 'ms';
        rio.observe(el);
      });
    } else {
      reveals.forEach(function (el) { el.classList.add('revealed'); });
    }
  }

  /* ── 启动 ─────────────────────────────────────── */

  function init() {
    if (meta('wiki-full') === '1') document.body.classList.add('wiki-full');
    renderNav();
    renderContent();
    buildPageBanner();
    renderToc();
    initTheme();
    initSearch();
    initNavToggle();
    initProgress();
    initCopyButtons();
    initLightbox();
    initSectionReveal();
    initCommandPalette();
    initReadSettings();
    initKeyboardNav();
    initLandingFx();
    initMockupCinematic();
    requestAnimationFrame(function () { document.body.classList.add('page-ready'); });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
