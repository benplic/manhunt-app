import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Account } from './Account'

const deleteAccount = vi.fn()

vi.mock('../api/auth', () => ({
  deleteAccount: (...args: unknown[]) => deleteAccount(...args),
}))

vi.mock('../api/session', () => ({
  withAuthRetry: async (fn: (token: string) => Promise<unknown>) => fn('tok'),
  SessionExpiredError: class SessionExpiredError extends Error {},
}))

vi.mock('../social/blockList', () => ({
  listBlockedPlayers: vi.fn(() => [{ playerId: 'p1', displayName: 'Ada' }]),
  unblockPlayer: vi.fn(),
  anonymizedName: vi.fn(() => 'Blocked Player #1'),
}))

import { listBlockedPlayers, unblockPlayer } from '../social/blockList'

afterEach(() => {
  cleanup()
})

beforeEach(() => {
  vi.mocked(listBlockedPlayers).mockReturnValue([{ playerId: 'p1', displayName: 'Ada' }])
  deleteAccount.mockReset()
})

describe('Account', () => {
  it('links privacy and can unblock', () => {
    const onClose = vi.fn()
    render(<Account onClose={onClose} onSignedOut={() => undefined} />)
    const privacy = screen.getByRole('link', { name: /privacy policy/i })
    expect(privacy).toHaveAttribute('href', 'https://benplic.github.io/manhunt-app/')
    fireEvent.click(screen.getByRole('button', { name: /unblock/i }))
    expect(unblockPlayer).toHaveBeenCalledWith('p1')
  })

  it('deletes the account and signs out', async () => {
    const onSignedOut = vi.fn()
    vi.spyOn(window, 'confirm').mockReturnValue(true)
    deleteAccount.mockResolvedValue(undefined)
    render(<Account onClose={() => undefined} onSignedOut={onSignedOut} />)
    fireEvent.click(screen.getByRole('button', { name: /delete account/i }))
    await vi.waitFor(() => {
      expect(deleteAccount).toHaveBeenCalledWith('tok')
      expect(onSignedOut).toHaveBeenCalled()
    })
  })
})
