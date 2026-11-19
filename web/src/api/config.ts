/** Public API origin. Same host as the Release iOS client unless overridden. */
export function apiBaseUrl(): string {
  const fromEnv = import.meta.env.VITE_API_BASE_URL as string | undefined
  if (fromEnv && fromEnv.trim()) {
    return fromEnv.replace(/\/$/, '')
  }
  return 'https://manhunt.pivotlattice.app'
}
