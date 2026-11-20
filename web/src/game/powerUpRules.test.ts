import { describe, expect, it } from 'vitest'
import { decide, requiresMapPoint, requiresPlayerTarget, requiresTarget } from './powerUpRules'

const base = {
  balance: 200,
  cost: 40,
  cooldownRemaining: 0,
  phase: 'active' as const,
  role: 'hider',
  requiredRole: 'hider',
  status: 'active' as const,
  requiresTarget: false,
  hasTarget: false,
  available: true,
}

describe('PowerUpRules', () => {
  it('flags targeted powers', () => {
    expect(requiresTarget('decoy')).toBe(true)
    expect(requiresTarget('shield')).toBe(false)
    expect(requiresMapPoint('create_safe')).toBe(true)
    expect(requiresPlayerTarget('rescue')).toBe(true)
  })

  it('denies insufficient points', () => {
    expect(decide({ ...base, balance: 5, cost: 40 }).kind).toBe('denied')
  })

  it('allows non-targeted purchase in active phase', () => {
    expect(decide(base).kind).toBe('allowed')
  })
})