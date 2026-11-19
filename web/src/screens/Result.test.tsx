import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import type { PlayerView } from '../api/types'
import { Result } from './Result'

const endedView: PlayerView = {
  game_id: 'game-1',
  join_code: 'ABCDEF',
  phase: 'ended',
  you: { player_id: 'u1', role: 'seeker', status: 'active', is_host: true },
  players: [],
  result: { winner: 'seekers', reason: 'all_hiders_tagged', ended_at: null },
}

describe('Result screen', () => {
  it('shows winner and reason from view.result', () => {
    render(<Result view={endedView} onDone={() => undefined} />)
    expect(screen.getByText(/seekers/i)).toBeInTheDocument()
    expect(screen.getByText(/all_hiders_tagged/i)).toBeInTheDocument()
  })

  it('calls onDone when leaving the result', async () => {
    const user = userEvent.setup()
    const onDone = vi.fn()
    render(<Result view={endedView} onDone={onDone} />)
    await user.click(screen.getByRole('button', { name: /done/i }))
    expect(onDone).toHaveBeenCalled()
  })
})
