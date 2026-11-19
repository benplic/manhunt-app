import { afterEach, describe, expect, it } from 'vitest'
import { clearActiveGame, loadActiveGameId, rememberActiveGame } from './resume'

afterEach(() => {
  sessionStorage.clear()
})

describe('resume', () => {
  it('remembers and clears the active game id', () => {
    rememberActiveGame('abc')
    expect(loadActiveGameId()).toBe('abc')
    clearActiveGame()
    expect(loadActiveGameId()).toBeNull()
  })
})
