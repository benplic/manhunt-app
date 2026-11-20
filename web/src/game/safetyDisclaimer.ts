const STORAGE_KEY = 'manhunt.safetyDisclaimerAcked'

/** Session fallback when localStorage is blocked (private mode / quota). */
let memoryAcked = false

export const SAFETY_DISCLAIMER_COPY =
  'Play only where it is legal and safe. You are responsible for your surroundings. ' +
  'Manhunt is not for reckless use on public roads or anywhere you could hurt yourself or others.'

export function needsSafetyDisclaimer(): boolean {
  if (memoryAcked) {
    return false
  }
  try {
    return localStorage.getItem(STORAGE_KEY) !== '1'
  } catch {
    // Private mode or blocked storage — show until this session acks in memory.
    return true
  }
}

export function ackSafetyDisclaimer(): void {
  memoryAcked = true
  try {
    localStorage.setItem(STORAGE_KEY, '1')
  } catch {
    // Memory ack above still gates the rest of this tab session.
  }
}

/** Test-only: clear both storage and the in-memory fallback. */
export function resetSafetyDisclaimerForTests(): void {
  memoryAcked = false
}
