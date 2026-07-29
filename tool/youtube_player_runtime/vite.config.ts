import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  build: {
    outDir: '../../assets/youtube_player',
    emptyOutDir: true,
    sourcemap: false,
    rollupOptions: {
      output: {
        entryFileNames: 'youtube_player.js',
        assetFileNames: 'youtube_player.[ext]',
      },
    },
  },
});
