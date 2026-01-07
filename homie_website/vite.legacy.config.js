import { defineConfig } from 'vite';
import { resolve, dirname } from 'path';
import { readdirSync, cpSync } from 'fs';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Dynamically discover all HTML files in the root directory
const htmlFiles = readdirSync('.').filter(file => file.endsWith('.html'));
const input = Object.fromEntries(
  htmlFiles.map(file => [
    file.replace('.html', ''),
    resolve(__dirname, file)
  ])
);

export default defineConfig({
  root: '.',
  publicDir: 'assets',
  server: {
    port: 3000,
    host: true, // Listen on all addresses
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      input,
    },
  },
  plugins: [
    {
      name: 'copy-inspiration-images',
      closeBundle() {
        // Copy inspiration-images folder to dist/assets after build
        cpSync(
          resolve(__dirname, 'assets/inspiration-images'),
          resolve(__dirname, 'dist/assets/inspiration-images'),
          { recursive: true }
        );
      }
    }
  ]
});
