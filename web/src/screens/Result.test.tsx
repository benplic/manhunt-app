import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import type { PlayerView } from '../api/types'
import { Result } from './Result'

const rematchGame = vi.fn()

vi.mock('../api/games', () => ({
  rematchGame: (...args: unknown[]) => rematchGame(...args),
}))

vi.mock('../api/session', () => ({
  withAuthRetry: async (fn: (token: string) => Promise<unknown>) => fn('tok'),
  SessionExpiredError: class SessionExpiredError extends Error {},
}))

const endedView: PlayerView = {
  game_id: 'game-1',
  join_code: 'ABCDEF',
  phase: 'ended',
  you: { player_id: 'u1', role: 'seeker', status: 'active', is_host: true },
  players: [],
  result: { winner: 'seekers', reason: 'All hiders were tagged.', ended_at: null },
}

describe('Result screen', () => {
  it('shows winner and reason from view.result', () => {
    render(
      <Result
        view={endedView}
        onDone={() => undefined}
        onRematch={() => undefined}
        onSignedOut={() => undefined}
      />,
    )
    expect(screen.getByText(/seekers win/i)).toBeInTheDocument()
    expect(screen.getByText(/all hiders were tagged/i)).toBeInTheDocument()
  })

  it('calls onDone when leaving the result', async () => {
    const user = userEvent.setup()
    const onDone = vi.fn()
    render(
      <Result
        view={endedView}
        onDone={onDone}
        onRematch={() => undefined}
        onSignedOut={() => undefined}
      />,
    )
    await user.click(screen.getByRole('button', { name: /home/i }))
    expect(onDone).toHaveBeenCalled()
  })

  it('starts a rematch', async () => {
    const user = userEvent.setup()
    const onRematch = vi.fn()
    rematchGame.mockResolvedValue({ ...endedView, phase: 'lobby', result: null })
    render(
      <Result
        view={endedView}
        onDone={() => undefined}
        onRematch={onRematch}
        onSignedOut={() => undefined}
      />,
    )
    await user.click(screen.getByRole('button', { name: /rematch/i }))
    expect(rematchGame).toHaveBeenCalled()
    expect(onRematch).toHaveBeenCalled()
  })
})
