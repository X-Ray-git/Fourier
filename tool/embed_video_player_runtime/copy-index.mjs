// 生产版 index.html 由本脚本写入构建产物目录。运行时为经典脚本（IIFE），
// 本地 Bilibili 页面通过普通 <script> 标签加载；YouTube 播放器由 Dart 侧
// 把同一个 bundle 注入真实 embed 页面，不走本页面。
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const outDir = join(root, '..', '..', 'assets', 'embed_video_player');

const html = `<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1.0, viewport-fit=cover"
    />
    <title>Fourier Video</title>
    <style>
      html,
      body,
      #video-container,
      video {
        width: 100%;
        height: 100%;
        margin: 0;
        padding: 0;
        overflow: hidden;
        background: #000;
      }

      #video-container {
        position: relative;
      }

      .shaka-video-container,
      .shaka-controls-container {
        font-family:
          -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif !important;
      }

      video {
        object-fit: contain;
      }

      .shaka-spinner-container,
      .shaka-spinner {
        display: none !important;
      }
    </style>
  </head>
  <body>
    <div id="video-container">
      <video id="video" autoplay playsinline></video>
    </div>
    <script src="./embed_video_player.js"></script>
  </body>
</html>
`;

mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'index.html'), html);
console.log(`wrote ${join(outDir, 'index.html')}`);
