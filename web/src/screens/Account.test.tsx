import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Account } from './Account'

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
})

describe('Account', () => {
  it('links privacy and can unblock', () => {
    const onClose = vi.fn()
    render(<Account onClose={onClose} />)
    const privacy = screen.getByRole('link', { name: /privacy policy/i })
    expect(privacy).toHaveAttribute('href', 'https://benplic.github.io/manhunt-app/')
    fireEvent.click(screen.getByRole('button', { name: /unblock/i }))
    expect(unblockPlayer).toHaveBeenCalledWith('p1')
  })
})
