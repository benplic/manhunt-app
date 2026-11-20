import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { EventLog } from './EventLog'

vi.mock('../api/session', () => ({
  SessionExpiredError: class SessionExpiredError extends Error {},
  withAuthRetry: (fn: (token: string) => Promise<unknown>) => fn('tok'),
}))

vi.mock('../api/games', () => ({
  fetchGameEvents: vi.fn(async () => ({
    events: [{ seq: 1, type: 'tag', payload: { text: 'Tagged Sam' } }],
  })),
}))

describe('EventLog', () => {
  it('renders timeline rows from the server', async () => {
    render(<EventLog gameId="g1" onClose={() => undefined} onSignedOut={() => undefined} />)
    await waitFor(() => {
      expect(screen.getByText(/tagged sam/i)).toBeInTheDocument()
    })
    expect(screen.getByText('tag')).toBeInTheDocument()
  })
})