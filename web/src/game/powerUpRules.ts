export type MatchPhase = 'lobby' | 'head_start' | 'active' | 'paused' | 'ended'

export type PlayerStatus = 'active' | 'eliminated' | 'signal_lost'

export type PurchaseDenial =
  | 'insufficientPoints'
  | 'coolingDown'
  | 'wrongPhase'
  | 'wrongRole'
  | 'eliminated'
  | 'needsTarget'
  | 'targetOutside'
  | 'unavailable'

export type PurchaseDecision =
  | { kind: 'allowed' }
  | { kind: 'denied'; reason: PurchaseDenial }

export type PurchaseRequest = {
  balance: number
  cost: number
  cooldownRemaining: number
  phase: MatchPhase
  role: string
  requiredRole: string
  status: PlayerStatus
  requiresTarget: boolean
  hasTarget: boolean
  targetInsidePlayArea?: boolean
  available?: boolean
}

export function requiresTarget(powerId: string): boolean {
  switch (powerId) {
    case 'decoy':
    case 'create_safe':
    case 'move_safe':
    case 'rescue':
      return true
    default:
      return false
  }
}

export function requiresMapPoint(powerId: string): boolean {
  switch (powerId) {
    case 'decoy':
    case 'create_safe':
    case 'move_safe':
      return true
    default:
      return false
  }
}

export function requiresPlayerTarget(powerId: string): boolean {
  return powerId === 'rescue'
}

export function requiresZoneTarget(powerId: string): boolean {
  return powerId === 'move_safe'
}

export function decide(request: PurchaseRequest): PurchaseDecision {
  if (request.balance < request.cost) {
    return { kind: 'denied', reason: 'insufficientPoints' }
  }
  if (request.cooldownRemaining > 0) {
    return { kind: 'denied', reason: 'coolingDown' }
  }
  if (request.phase !== 'active') {
    return { kind: 'denied', reason: 'wrongPhase' }
  }
  if (request.role !== request.requiredRole) {
    return { kind: 'denied', reason: 'wrongRole' }
  }
  if (request.status === 'eliminated') {
    return { kind: 'denied', reason: 'eliminated' }
  }
  if (request.available === false) {
    return { kind: 'denied', reason: 'unavailable' }
  }
  if (request.requiresTarget && !request.hasTarget) {
    return { kind: 'denied', reason: 'needsTarget' }
  }
  if (
    request.requiresTarget &&
    request.hasTarget &&
    request.targetInsidePlayArea === false
  ) {
    return { kind: 'denied', reason: 'targetOutside' }
  }
  return { kind: 'allowed' }
}

export function denialMessage(reason: PurchaseDenial): string {
  switch (reason) {
    case 'insufficientPoints':
      return 'Not enough points.'
    case 'coolingDown':
      return 'That power is on cooldown.'
    case 'wrongPhase':
      return 'Powers are only available during the hunt.'
    case 'wrongRole':
      return 'Wrong role for that power.'
    case 'eliminated':
      return 'You are out of the hunt.'
    case 'needsTarget':
      return 'Pick a target on the map or list.'
    case 'targetOutside':
      return 'That point is outside the play area.'
    case 'unavailable':
      return 'That power is unavailable in this game.'
    default:
      return 'Cannot use that power right now.'
  }
}

export function chipIsTappable(request: PurchaseRequest): boolean {
  const d = decide(request)
  if (d.kind === 'allowed') {
    return true
  }
  if (d.reason === 'needsTarget') {
    const probe = { ...request, hasTarget: true }
    return decide(probe).kind === 'allowed'
  }
  return false
}

export function chipShowsDenialOnTap(request: PurchaseRequest): boolean {
  const d = decide(request)
  return d.kind === 'denied' && d.reason === 'unavailable'
}