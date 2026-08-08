/*
 * Auto Folo Wiki — 共享工具（浏览器与 Node 双端可用）
 * 经典 script 格式：浏览器挂载 window.WikiCommon，Node 通过 require 使用。
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.WikiCommon = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // 与 GitHub 一致的标题锚点 slug 规则：
  // 转小写、空格与全角空格转 '-'、去除标点与符号、保留中文字符、合并连续 '-'
  function slugify(text) {
    return String(text)
      .normalize('NFKC')
      .toLowerCase()
      .trim()
      .replace(
        /[\u2000-\u206f\u2e00-\u2e7f'!"#$%&()*+,./:;<=>?@[\]^`{|}~\u3002\uff0c\u3001\uff1f\uff01\uff1a\uff1b\u201c\u201d\u2018\u2019\u2014\u2026\u300a\u300b\uff08\uff09\u00b7]/g,
        ''
      )
      .replace(/[\s\u3000]+/g, '-')
      .replace(/-+/g, '-');
  }

  // 反转转换器对 </script 的转义
  function unescapeScriptClose(text) {
    return text.replace(/<\\\/script/gi, '</script');
  }

  // 规范化相对路径：去除 . 段，消费 .. 段；越界的 .. 保留为前缀（用于判断是否逃出某个根）
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

  // 从 dir（wiki 根相对）构造指向 target（wiki 根相对）的页面相对链接
  function relFromDir(dir, target) {
    const depth = dir ? dir.split('/').filter(Boolean).length : 0;
    return '../'.repeat(depth) + target;
  }

  return { slugify: slugify, unescapeScriptClose: unescapeScriptClose, normalizeRel: normalizeRel, relFromDir: relFromDir };
});
