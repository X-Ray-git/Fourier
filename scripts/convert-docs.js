#!/usr/bin/env node
/*
 * Auto Folo Wiki — 一次性 .md → .html 转换器
 *
 * 用法：
 *   node scripts/convert-docs.js                # 转换 docs/agent_handoff 下全部 .md
 *   node scripts/convert-docs.js --root         # 额外把 home.md 生成为根 index.html
 *
 * 规则：
 *  - 正文（Markdown）写入 <script type="text/markdown" id="wiki-content">
 *  - </script 序列转义为 <\/script，渲染时由 app.js 还原
 *  - 内部链接 .md → .html（含 #锚点），wiki 根内的 README.md → 根 index.html
 *  - 指向 wiki 根之外的 .md（如 THIRD_PARTY_NOTICES.md）保持原样
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const WIKI = path.join(ROOT, 'docs', 'agent_handoff');

const SKIP_FILES = new Set(['home.md']);

function normalizeRel(p) {
  const out = [];
  let escaped = 0;
  for (const seg of p.split('/')) {
    if (seg === '' || seg === '.') continue;
    if (seg === '..') {
      if (out.length) out.pop();
      else escaped++;
    } else {
      out.push(seg);
    }
  }
  return '../'.repeat(escaped) + out.join('/');
}

function joinRel(dir, rel) {
  return normalizeRel((dir ? dir + '/' : '') + rel);
}

// 保护代码块与行内代码，只改写正文中的链接
function rewriteLinks(md, ctx) {
  const fenced = md.split(/(```[^\n]*\n[\s\S]*?```|~~~[^\n]*\n[\s\S]*?~~~)/g);
  return fenced
    .map((part, i) => {
      if (i % 2 === 1) return part; // 围栏代码块，不改写
      const inlines = part.split(/(`[^`\n]+`)/g);
      return inlines
        .map((seg, j) => {
          if (j % 2 === 1) return seg; // 行内代码，不改写
          return seg.replace(/\]\(([^)\s]+)\)/g, (m, href) => '](' + rewriteHref(href, ctx) + ')');
        })
        .join('');
    })
    .join('');
}

function splitFrag(href) {
  const i = href.indexOf('#');
  if (i === -1) return { target: href, frag: '' };
  return { target: href.slice(0, i), frag: href.slice(i) };
}

function rewriteHref(href, ctx) {
  if (/^(https?:|mailto:|tel:|#)/.test(href)) return href;
  const { target, frag } = splitFrag(href);
  if (!target) return href;
  const isMd = /\.md$/i.test(target);
  const resolved = joinRel(ctx.dir, target); // 相对 wiki 根（可能带 .. 前缀）
  const escapesWiki = resolved.startsWith('../');
  const depth = ctx.dir ? ctx.dir.split('/').filter(Boolean).length : 0;
  const toPage = (wikiRel) => '../'.repeat(depth) + wikiRel;

  if (isMd) {
    if (!escapesWiki) {
      const htmlRel = resolved.replace(/\.md$/i, '.html');
      if (htmlRel === 'index.html') {
        // wiki 内 README.md → 仓库根首页
        const toRoot = '../'.repeat(depth + 2) + 'index.html';
        return toRoot + frag;
      }
      if (ctx.rootMode) return 'docs/agent_handoff/' + htmlRel + frag;
      return toPage(htmlRel) + frag;
    }
    // 指向 wiki 根之外（仓库根的 .md 数据文件，如 THIRD_PARTY_NOTICES.md）
    if (ctx.rootMode) {
      const rebased = resolved.replace(/^(\.\.\/)+/, '');
      return rebased + frag;
    }
    return href; // 保持原样（相对页面，.md 不变）
  }
  if (ctx.rootMode && !escapesWiki) {
    return 'docs/agent_handoff/' + resolved + frag;
  }
  return href;
}

function escapeScriptClose(s) {
  return s.replace(/<\/script/gi, '<\\/script');
}

function pageTitle(md) {
  const m = md.match(/^#\s+(.+?)\s*$/m);
  return m ? m[1].trim() : '未命名页面';
}

const TEMPLATE = `<!DOCTYPE html>
<html lang="zh-CN" data-theme="auto">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="wiki-base" content="__WIKI_BASE__">
<meta name="repo-root" content="__REPO_ROOT__">
__WIKI_FULL__
<title>__TITLE__ · Auto Folo Wiki</title>
<link rel="stylesheet" href="__WIKI_BASE__/assets/theme.css">
</head>
<body>
<header class="wiki-header">
  <div class="wiki-header-inner">
    <button class="nav-toggle" type="button" aria-label="切换导航">☰</button>
    <a class="brand" href="__REPO_ROOT__/index.html">
      <span class="brand-mark" aria-hidden="true"></span>
      <span class="brand-name">Auto Folo Wiki</span>
    </a>
    <div class="header-tools">
      <div class="search-box">
        <input id="wiki-search-input" type="search" placeholder="搜索文档…" autocomplete="off" aria-label="搜索文档">
      </div>
      <button id="theme-toggle" type="button" class="theme-toggle" aria-label="切换明暗主题" title="切换明暗主题">
        <svg class="theme-icon-auto" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>
        <svg class="theme-icon-light" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>
        <svg class="theme-icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>
        <svg class="theme-icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>
      </button>
    </div>
  </div>
  <div id="search-results" class="search-results" hidden></div>
</header>
<div class="wiki-layout">
  <nav id="wiki-nav" class="wiki-nav" aria-label="站点导航"></nav>
  <div class="wiki-content-col">
    <main class="wiki-main">
      <article>
        <div id="wiki-rendered" class="wiki-rendered"></div>
      </article>
    </main>
    <footer class="wiki-footer">
      <span>Auto Folo Wiki · <a href="__REPO_ROOT__/LICENSE">AGPL-3.0</a></span>
      <a href="__REPO_ROOT__/docs/agent_handoff/meta/site-guide.html">站点指南</a>
      <a href="__REPO_ROOT__/docs/agent_handoff/meta/migration-map.html">迁移映射</a>
      <a href="__REPO_ROOT__/AGENT_HANDOFF.md">交接入口</a>
    </footer>
  </div>
  <nav id="wiki-toc" class="wiki-toc" aria-label="本页目录"></nav>
</div>
<script type="text/markdown" id="wiki-content">
__CONTENT__
</script>
<script src="__WIKI_BASE__/assets/wiki-common.js"></script>
<script src="__WIKI_BASE__/assets/vendor/markdown-it.min.js"></script>
<script src="__WIKI_BASE__/assets/vendor/markdown-it-anchor.umd.js"></script>
<script src="__WIKI_BASE__/assets/data/nav.js"></script>
<script src="__WIKI_BASE__/assets/data/search-index.js"></script>
<script src="__WIKI_BASE__/assets/app.js"></script>
</body>
</html>
`;

function depthOf(relDir) {
  return relDir ? relDir.split('/').filter(Boolean).length : 0;
}

function wikiBaseFor(relDir) {
  const d = depthOf(relDir);
  return d === 0 ? '.' : '../'.repeat(d).replace(/\/$/, '');
}

function convertFile(relPath, rootMode) {
  const absMd = path.join(WIKI, relPath);
  const md = fs.readFileSync(absMd, 'utf8');
  const dir = path.dirname(relPath).replace(/^\.$/, '');

  const ctx = { dir, rootMode };
  const rewritten = rewriteLinks(md, ctx);
  const title = pageTitle(md);
  const content = escapeScriptClose(rewritten);

  let wikiBase, repoRoot, outPath;
  if (rootMode) {
    wikiBase = 'docs/agent_handoff';
    repoRoot = '.';
    outPath = path.join(ROOT, 'index.html');
  } else {
    wikiBase = wikiBaseFor(dir);
    repoRoot = wikiBase === '.' ? '../..' : wikiBase + '/../..';
    outPath = path.join(WIKI, dir, path.basename(relPath).replace(/\.md$/i, '.html'));
  }

  const html = TEMPLATE
    .replace(/__WIKI_BASE__/g, wikiBase)
    .replace(/__REPO_ROOT__/g, repoRoot)
    .replace('__WIKI_FULL__', rootMode ? '<meta name="wiki-full" content="1">' : '')
    .replace('__TITLE__', () => title)
    // 必须用函数替换：content 中的 `$'` 等序列会被字符串替换解释为模板片段
    .replace('__CONTENT__', () => content);

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, html);
  console.log('converted:', relPath, '->', path.relative(ROOT, outPath), '| title:', title);
  return outPath;
}

function collectMd(dir, acc) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'assets') continue;
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) collectMd(p, acc);
    else if (/\.md$/i.test(entry.name) && !SKIP_FILES.has(entry.name)) acc.push(p);
  }
  return acc;
}

function main() {
  const rootMode = process.argv.includes('--root');
  const mdFiles = collectMd(WIKI, []);
  mdFiles.sort();
  for (const abs of mdFiles) {
    const rel = path.relative(WIKI, abs);
    convertFile(rel, false);
  }
  if (rootMode) {
    const homeAbs = path.join(WIKI, 'home.md');
    if (fs.existsSync(homeAbs)) {
      convertFile('home.md', true);
    } else {
      console.log('home.md 不存在（首页已是直接编辑的 index.html），跳过。');
    }
  }
  console.log('done. pages:', mdFiles.length + (rootMode ? 1 : 0));
}

main();
