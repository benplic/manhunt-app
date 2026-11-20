const STORAGE_KEY = 'manhunt.safetyDisclaimerAcked'

export const SAFETY_DISCLAIMER_COPY =
  'Play only where it is legal and safe. You are responsible for your surroundings. ' +
  'Manhunt is not for reckless use on public roads or anywhere you could hurt yourself or others.'

export function needsSafetyDisclaimer(): boolean {
  try {
    return localStorage.getItem(STORAGE_KEY) !== '1'
  } catch {
    // Private mode or blocked storage — show once per session via caller fallback.
    return true
  }
}

export function ackSafetyDisclaimer(): void {
  try {
    localStorage.setItem(STORAGE_KEY, '1')
  } catch {
    // TODO: persist ack in memory when storage is unavailable.
  }
}