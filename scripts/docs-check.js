#!/usr/bin/env node
/*
 * Auto Folo Wiki — 一致性检查（零依赖，Node 18+）
 *
 *   node scripts/docs-check.js
 *
 * 检查项：
 *  1. 每个页面 wiki-content 脚本块完整且无未转义的 </script
 *  2. 页内/页间链接与锚点：相对链接目标存在，`#锚点` 在目标页中存在
 *  3. 指向 wiki 根的 .md 链接不应残留（README 链接除外处理）
 *  4. 页面不得使用 fetch()/ES Module/动态 import/http(s) 资源
 *  5. 敏感信息扫描：私有路径、Token、API Key、账号标识
 *  6. 历史页必须带“历史资料”横幅
 *  7. 导航清单（nav.js）中的每个页面必须存在
 *  8. 搜索索引新鲜度（manifest 与页面内容哈希一致）
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const WIKI = path.join(ROOT, 'docs', 'agent_handoff');

const markdownit = require(path.join(WIKI, 'assets', 'vendor', 'markdown-it.min.js'));
const markdownItAnchor = require(path.join(WIKI, 'assets', 'vendor', 'markdown-it-anchor.umd.js'));
const WikiCommon = require(path.join(WIKI, 'assets', 'wiki-common.js'));

const md = markdownit({ html: true });
md.use(markdownItAnchor, { slugify: WikiCommon.slugify });

let errors = 0;
let warnings = 0;

function err(msg) { errors++; console.error('ERROR  ', msg); }
function warn(msg) { warnings++; console.error('WARN   ', msg); }
function ok(msg) { console.log('ok     ', msg); }

function collectHtml(dir, acc) {
  if (!fs.existsSync(dir)) return acc;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'assets') continue;
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) collectHtml(p, acc);
    else if (/\.html$/i.test(entry.name)) acc.push(p);
  }
  return acc;
}

const SENSITIVE = [
  { re: /\/Users\/[^/\s]+/g, name: '本机私有路径' },
  { re: /\b(__Secure-better-auth\.session_token\s*=\s*)[A-Za-z0-9._-]{16,}/g, name: '真实 Session Token' },
  { re: /\bsk-[A-Za-z0-9]{20,}/g, name: 'DeepSeek/OpenAI API Key' },
  { re: /\bapi[_-]?key["']?\s*[:=]\s*["'][A-Za-z0-9]{20,}["']/gi, name: 'API Key 赋值' },
  { re: /Bearer\s+[A-Za-z0-9._-]{20,}/g, name: 'Bearer Token' },
  { re: /(?:auth|token|cookie)\s*[:=]\s*["'][A-Za-z0-9+/=_\-.]{40,}["']/gi, name: '疑似凭据字面量' },
];

function scanSensitive(text, file) {
  for (const rule of SENSITIVE) {
    const m = text.match(rule.re);
    if (m) err(`敏感信息（${rule.name}）: ${file} → ${m[0].slice(0, 60)}`);
  }
}

function pageInfo(abs) {
  const html = fs.readFileSync(abs, 'utf8');
  const contentM = html.match(/<script type="text\/markdown" id="wiki-content">([\s\S]*?)<\/script>/);
  const rawContent = contentM ? contentM[1] : '';
  const content = rawContent ? WikiCommon.unescapeScriptClose(rawContent) : '';
  return { html, rawContent, content, rendered: content ? md.render(content) : '' };
}

function collectIds(rendered) {
  const ids = new Set();
  for (const m of rendered.matchAll(/\sid="([^"]+)"/g)) ids.add(m[1]);
  return ids;
}

function resolveTarget(relDir, href) {
  if (/^(https?:|mailto:|tel:)/.test(href) || href.startsWith('#')) return null;
  const fragI = href.indexOf('#');
  const target = fragI === -1 ? href : href.slice(0, fragI);
  const frag = fragI === -1 ? '' : href.slice(fragI + 1);
  const resolved = WikiCommon.normalizeRel((relDir ? relDir + '/' : '') + target);
  return { resolved, frag };
}

function main() {
  const files = collectHtml(WIKI, []);
  files.sort();
  const rootIndex = path.join(ROOT, 'index.html');
  if (fs.existsSync(rootIndex)) files.push(rootIndex);

  const pages = new Map(); // abs -> info
  for (const abs of files) {
    const info = pageInfo(abs);
    pages.set(abs, info);
    const rel = path.relative(ROOT, abs);

    // 1. 转义完整性（检查未还原的原始内容）
    if (!info.content) err(`缺少 wiki-content: ${rel}`);
    if (info.rawContent.includes('</script')) err(`未转义的 </script: ${rel}`);

    // 2. 渲染
    if (!info.rendered) continue;

    // 4. 页面技术约束（仅扫描页面自身的 HTML 结构，正文中的示例文字不计）
    if (/type\s*=\s*["']module["']/.test(info.html)) err(`页面使用 ES Module: ${rel}`);
    if (/<script[^>]*>\s*import\s*\(/i.test(info.html)) err(`页面使用动态 import: ${rel}`);
    const pageBody = info.html.replace(/<script type="text\/markdown"[\s\S]*?<\/script>/, '');
    if (/<script[^>]*src="https?:\/\//.test(pageBody)) err(`页面引用远程脚本: ${rel}`);
    if (/<link[^>]*href="https?:\/\//.test(pageBody)) err(`页面引用远程样式: ${rel}`);

    // 6. 历史横幅
    if (rel.includes('history/archive/') || rel.endsWith('history/timeline.html')) {
      if (!info.content.includes('历史资料')) err(`历史页缺少横幅: ${rel}`);
    }

    // 5. 敏感扫描
    scanSensitive(info.content, rel);
  }

  // 2. 链接与锚点检查
  function resolveAbs(fromAbs, href) {
    const fragI = href.indexOf('#');
    const target = fragI === -1 ? href : href.slice(0, fragI);
    const frag = fragI === -1 ? '' : href.slice(fragI + 1);
    return { abs: path.resolve(path.dirname(fromAbs), target), frag };
  }

  const inWiki = (abs) => {
    const rel = path.relative(WIKI, abs);
    return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
  };

  for (const [abs, info] of pages) {
    const rel = path.relative(ROOT, abs);
    const ids = collectIds(info.rendered);
    const linkRe = /<a\b[^>]*href="([^"]+)"/g;
    let m;
    while ((m = linkRe.exec(info.rendered))) {
      const href = m[1];
      if (/^(https?:|mailto:|tel:)/.test(href)) continue;
      if (href.startsWith('#')) {
        if (!ids.has(href.slice(1))) err(`同页锚点缺失: ${rel} → ${href}`);
        continue;
      }
      const { abs: absTarget, frag } = resolveAbs(abs, href);
      if (!fs.existsSync(absTarget)) {
        err(`链接目标不存在: ${rel} → ${href}`);
        continue;
      }
      if (frag) {
        const tInfo = pages.get(absTarget);
        if (tInfo) {
          const tIds = collectIds(tInfo.rendered);
          if (!tIds.has(frag)) err(`跨页锚点缺失: ${rel} → ${href}`);
        }
      }
    }
    // 图片与静态资源引用（基于渲染结果，避免正文示例被误判）
    const srcRe = /<(?:img|source)\b[^>]*src="([^"]+)"/g;
    while ((m = srcRe.exec(info.rendered))) {
      const src = m[1];
      if (/^(https?:|data:)/.test(src)) continue;
      const { abs: absTarget } = resolveAbs(abs, src);
      if (!fs.existsSync(absTarget)) err(`资源缺失: ${rel} → ${src}`);
    }
    // 脚本引用（基于页面 HTML 自身，排除 wiki-content 块）
    const pageBody = info.html.replace(/<script type="text\/markdown"[\s\S]*?<\/script>/, '');
    const scriptRe = /<script\b[^>]*src="([^"]+)"/g;
    while ((m = scriptRe.exec(pageBody))) {
      const src = m[1];
      if (/^(https?:)/.test(src)) continue;
      const { abs: absTarget } = resolveAbs(abs, src);
      if (!fs.existsSync(absTarget)) err(`脚本缺失: ${rel} → ${src}`);
    }
    // 样式表引用
    const linkRe2 = /<link\b[^>]*href="([^"]+)"/g;
    while ((m = linkRe2.exec(info.html))) {
      const href = m[1];
      if (/^(https?:)/.test(href)) continue;
      const { abs: absTarget } = resolveAbs(abs, href);
      if (!fs.existsSync(absTarget)) err(`样式缺失: ${rel} → ${href}`);
    }
  }

  // 3. 残留 .md 内部链接（正文中不应再有指向 wiki 内的 .md）
  for (const [abs, info] of pages) {
    const rel = path.relative(ROOT, abs);
    for (const m of info.content.matchAll(/\]\(([^)\s]+\.md[^)\s]*)\)/g)) {
      const href = m[1];
      if (/^https?:/.test(href)) continue;
      const { abs: absTarget } = resolveAbs(abs, href);
      if (inWiki(absTarget) && !href.endsWith('README.md')) {
        err(`残留 .md 内部链接: ${rel} → ${href}`);
      }
    }
  }

  // 7. 导航完整性
  const navPath = path.join(WIKI, 'assets', 'data', 'nav.js');
  const navSrc = fs.readFileSync(navPath, 'utf8');
  const navMatches = [...navSrc.matchAll(/path:\s*'([^']+)'/g)];
  for (const m of navMatches) {
    const p = m[1];
    const absTarget = p === 'index.html' ? path.join(ROOT, p) : path.join(WIKI, p);
    if (!fs.existsSync(absTarget)) err(`导航指向不存在的页面: ${p}`);
  }
  ok(`nav 条目 ${navMatches.length} 个`);

  // 8. 索引新鲜度
  const indexPath = path.join(WIKI, 'assets', 'data', 'search-index.js');
  if (!fs.existsSync(indexPath)) {
    err('搜索索引缺失，请运行 ./scripts/docs.sh index');
  } else {
    const idxSrc = fs.readFileSync(indexPath, 'utf8');
    const manifestM = idxSrc.match(/WIKI_SEARCH_MANIFEST = "([0-9a-f]+)"/);
    const crypto = require('crypto');
    const digest = crypto.createHash('sha256');
    for (const [abs] of pages) digest.update(fs.readFileSync(abs, 'utf8'));
    const expect = digest.digest('hex').slice(0, 16);
    if (!manifestM || manifestM[1] !== expect) {
      err('搜索索引过期，请运行 ./scripts/docs.sh index');
    } else {
      ok('搜索索引最新');
    }
  }

  console.log('----');
  if (errors) {
    console.error(`${errors} errors, ${warnings} warnings`);
    process.exit(1);
  }
  console.log(`通过：${files.length} 页，${warnings} warnings`);
}

main();
