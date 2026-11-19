/** Shared copy for tag failures so LiveMap and QrScan stay aligned. */

export const ACCURACY_CUTOFF_M = 30

export function isAccuracyTooFuzzy(accuracyM: number | null | undefined): boolean {
  return accuracyM == null || accuracyM > ACCURACY_CUTOFF_M
}

export function localAccuracyBlockMessage(accuracyM: number): string {
  return `GPS is too fuzzy to tag (${Math.round(accuracyM)} m). Wait for a clearer fix.`
}
