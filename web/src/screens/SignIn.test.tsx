import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { SignIn } from './SignIn'

const signInDev = vi.fn()

vi.mock('../api/auth', () => ({
  signInDev: (...args: unknown[]) => signInDev(...args),
  TooYoungError: class TooYoungError extends Error {
    constructor() {
      super('Manhunt is not available for people under 13.')
      this.name = 'TooYoungError'
    }
  },
}))

describe('SignIn screen', () => {
  beforeEach(() => {
    signInDev.mockReset()
    localStorage.clear()
  })

  it('shows privacy and support links', () => {
    render(<SignIn onSignedIn={() => undefined} />)
    const privacy = screen.getByRole('link', { name: /privacy/i })
    expect(privacy).toHaveAttribute('href', 'https://benplic.github.io/manhunt-app/')
    const support = screen.getByRole('link', { name: /support/i })
    expect(support).toHaveAttribute('href', 'mailto:support@manhunt.pivotlattice.app')
  })

  it('calls signInDev and onSignedIn on Play', async () => {
    const user = userEvent.setup()
    const onSignedIn = vi.fn()
    signInDev.mockResolvedValue({
      access_token: 'tok',
      expires_at: '2099-01-01T00:00:00+00:00',
      user: { id: 'u1', display_name: 'Casey', avatar_url: null },
      refresh_token: 'ref',
    })

    render(<SignIn onSignedIn={onSignedIn} />)
    await user.type(screen.getByLabelText(/display name/i), 'Casey')
    await user.type(screen.getByLabelText(/^age$/i), '18')
    await user.type(screen.getByLabelText(/home key/i), 'party-secret')
    await user.click(screen.getByRole('button', { name: /play/i }))

    await waitFor(() => {
      expect(signInDev).toHaveBeenCalledWith({
        displayName: 'Casey',
        age: 18,
        homeKey: 'party-secret',
      })
      expect(onSignedIn).toHaveBeenCalled()
    })
  })

  it('shows an error when age is under 13', async () => {
    const user = userEvent.setup()
    render(<SignIn onSignedIn={() => undefined} />)
    await user.type(screen.getByLabelText(/display name/i), 'Kid')
    await user.type(screen.getByLabelText(/^age$/i), '12')
    await user.type(screen.getByLabelText(/home key/i), 'party-secret')
    await user.click(screen.getByRole('button', { name: /play/i }))

    expect(await screen.findByText(/under 13/i)).toBeInTheDocument()
    expect(signInDev).not.toHaveBeenCalled()
  })
})
