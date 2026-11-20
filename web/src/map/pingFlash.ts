export type RevealIdSource = { reveal_id: string }

/** Returns ids that appeared since the previous view snapshot. */
export function newRevealIds(
  prev: RevealIdSource[] | undefined,
  next: RevealIdSource[] | undefined,
): string[] {
  const seen = new Set((prev ?? []).map((r) => r.reveal_id))
  return (next ?? []).filter((r) => !seen.has(r.reveal_id)).map((r) => r.reveal_id)
}