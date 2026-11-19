import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

// Default API is the public Manhunt host; override with VITE_API_BASE_URL.
export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
  },
})
