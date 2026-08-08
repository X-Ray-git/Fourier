#!/usr/bin/env node
/*
 * Auto Folo Wiki — 搜索索引生成器（零依赖，Node 18+）
 * 扫描 docs/agent_handoff 下所有 .html 与根 index.html，
 * 提取 wiki-content 中的 Markdown，用仓库内置 markdown-it 渲染后抽取标题/锚点/正文，
 * 输出经典脚本数据文件 docs/agent_handoff/assets/data/search-index.js。
 * 索引随内容提交；阅读端不需要再运行任何生成过程。
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const WIKI = path.join(ROOT, 'docs', 'agent_handoff');
const OUT = path.join(WIKI, 'assets', 'data', 'search-index.js');

const markdownit = require(path.join(WIKI, 'assets', 'vendor', 'markdown-it.min.js'));
const markdownItAnchor = require(path.join(WIKI, 'assets', 'vendor', 'markdown-it-anchor.umd.js'));
const WikiCommon = require(path.join(WIKI, 'assets', 'wiki-common.js'));

const md = markdownit({ html: true });
md.use(markdownItAnchor, { slugify: WikiCommon.slugify });

function extractContent(html) {
  const m = html.match(/<script type="text\/markdown" id="wiki-content">([\s\S]*?)<\/script>/);
  return m ? WikiCommon.unescapeScriptClose(m[1]) : '';
}

function stripHtml(s) {
  return s
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

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

function main() {
  const files = collectHtml(WIKI, []);
  files.sort();
  // 根首页最后扫描（保证排序），路径以 index.html 表示
  const rootIndex = path.join(ROOT, 'index.html');
  const entries = [];
  const digest = crypto.createHash('sha256');

  function processPage(abs, relPath) {
    const html = fs.readFileSync(abs, 'utf8');
    digest.update(html);
    const content = extractContent(html);
    if (!content) {
      console.warn('skip (no wiki-content):', relPath);
      return;
    }
    const rendered = md.render(content);
    const titleM = rendered.match(/<h1[^>]*>([\s\S]*?)<\/h1>/);
    const title = titleM ? stripHtml(titleM[1]) : path.basename(relPath, '.html');
    const headings = [];
    for (const m of rendered.matchAll(/<h([23]) id="([^"]+)"[^>]*>([\s\S]*?)<\/h\1>/g)) {
      headings.push({ id: m[2], text: stripHtml(m[3]) });
    }
    const text = stripHtml(rendered).slice(0, 3000);
    entries.push({ path: relPath, title, headings, text });
  }

  for (const abs of files) {
    const rel = path.relative(WIKI, abs);
    processPage(abs, rel);
  }
  if (fs.existsSync(rootIndex)) {
    processPage(rootIndex, 'index.html');
  }

  const manifest = digest.digest('hex').slice(0, 16);
  const js =
    '/* 由 scripts/docs-index.js 生成，随内容提交；阅读端零生成。 */\n' +
    'window.WIKI_SEARCH_MANIFEST = "' + manifest + '";\n' +
    'window.WIKI_SEARCH_INDEX = ' + JSON.stringify(entries, null, 1) + ';\n';
  fs.writeFileSync(OUT, js);
  console.log('index written:', OUT, '| pages:', entries.length, '| manifest:', manifest);
}

main();
