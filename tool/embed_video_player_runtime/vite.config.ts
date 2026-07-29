import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  build: {
    outDir: '../../assets/embed_video_player',
    emptyOutDir: true,
    sourcemap: false,
    rollupOptions: {
      output: {
        entryFileNames: 'embed_video_player.js',
        assetFileNames: 'embed_video_player.[ext]',
      },
    },
  },
});
