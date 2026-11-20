import { describe, expect, it } from 'vitest'
import { ApiError } from '../api/client'
import { closedGameMessage, isClosedGameError } from './rejoin'

describe('rejoin closed-game detection', () => {
  it('treats GAME_NOT_FOUND, NOT_A_MEMBER, WRONG_PHASE, and bare 404 as closed', () => {
    expect(isClosedGameError(new ApiError('GAME_NOT_FOUND', 'gone', 404))).toBe(true)
    expect(isClosedGameError(new ApiError('NOT_A_MEMBER', 'out', 403))).toBe(true)
    expect(isClosedGameError(new ApiError('WRONG_PHASE', 'closed', 409))).toBe(true)
    expect(isClosedGameError(new ApiError('INTERNAL', 'proxy', 404))).toBe(true)
    expect(isClosedGameError(new ApiError('RATE_LIMITED', 'slow', 429))).toBe(false)
    expect(isClosedGameError(new Error('network'))).toBe(false)
  })

  it('explains closed hunts in plain language', () => {
    expect(closedGameMessage(new ApiError('GAME_NOT_FOUND', 'x', 404))).toMatch(/gone|finished/i)
    expect(closedGameMessage(new ApiError('NOT_A_MEMBER', 'x', 403))).toMatch(/no longer in/i)
    expect(closedGameMessage(new ApiError('WRONG_PHASE', 'x', 409))).toMatch(/closed/i)
  })
})
