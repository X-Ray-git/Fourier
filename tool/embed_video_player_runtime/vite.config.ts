import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  build: {
    outDir: '../../assets/embed_video_player',
    emptyOutDir: true,
    sourcemap: false,
    modulePreload: false,
    rollupOptions: {
      input: 'src/main.ts',
      output: {
        // Classic-script (IIFE) build: the bundle is injected into the real
        // YouTube embed page via runJavaScript, where ES module syntax cannot
        // run. The local Bilibili page loads the same bundle with a plain
        // <script> tag.
        format: 'iife',
        entryFileNames: 'embed_video_player.js',
        assetFileNames: 'embed_video_player.[ext]',
      },
    },
  },
});
