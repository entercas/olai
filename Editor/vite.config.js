import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

// Everything is inlined into one editor.html: the app loads it with loadFileURL and
// must build without Node, so no side-car assets.
export default defineConfig({
  plugins: [viteSingleFile()],
  build: {
    target: 'safari17',
    cssCodeSplit: false,
    assetsInlineLimit: 100000000,
    chunkSizeWarningLimit: 4000,
  },
})
