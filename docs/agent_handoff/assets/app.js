/*
 * Auto Folo Wiki — 页面运行时
 * 经典 script：加载后渲染导航、Markdown 正文、目录、搜索与主题切换。
 * 不依赖 ES Module、fetch、Service Worker 或任何网络资源，file:// 下可用。
 */
(function () {
  'use strict';

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
    btn.addEventListener('click', function () {
      var order = ['auto', 'light', 'dark'];
      var next = order[(order.indexOf(readTheme()) + 1) % order.length];
      applyTheme(next);
    });
    // 跟随系统主题变化（仅 auto 模式）
    if (window.matchMedia) {
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () {
        if (readTheme() === 'auto') applyTheme('auto');
      });
    }
  }

  /* ── 搜索 ─────────────────────────────────────── */

  function initSearch() {
    var input = $('#wiki-search-input');
    var panel = $('#search-results');
    if (!input || !panel) return;
    var index = (typeof window.WIKI_SEARCH_INDEX !== 'undefined') ? window.WIKI_SEARCH_INDEX : [];
    var active = -1;
    var items = [];

    function norm(s) { return (s || '').toLowerCase(); }

    function score(entry, q) {
      var s = 0;
      var ql = norm(q);
      if (norm(entry.title).indexOf(ql) !== -1) s += 100;
      entry.headings.forEach(function (h) {
        if (norm(h.text).indexOf(ql) !== -1) s += 30;
      });
      var body = norm(entry.text);
      if (body.indexOf(ql) !== -1) s += 10;
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

    function render(q) {
      items = [];
      active = -1;
      panel.innerHTML = '';
      if (!q) { panel.hidden = true; return; }
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
      panel.hidden = false;
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
      else if (e.key === 'Escape') { panel.hidden = true; input.blur(); }
    });
    input.addEventListener('blur', function () {
      setTimeout(function () { panel.hidden = true; }, 150);
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

  /* ── 启动 ─────────────────────────────────────── */

  function init() {
    renderNav();
    renderContent();
    renderToc();
    initTheme();
    initSearch();
    initNavToggle();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
