import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../api/client'
import { QrScan } from './QrScan'

const claimQrTag = vi.fn()

vi.mock('../api/games', () => ({
  claimQrTag: (...args: unknown[]) => claimQrTag(...args),
}))

vi.mock('../api/session', () => ({
  withAuthRetry: async (fn: (token: string) => Promise<unknown>) => fn('tok'),
  SessionExpiredError: class SessionExpiredError extends Error {},
}))

vi.mock('html5-qrcode', () => ({
  Html5Qrcode: class {
    static getCameras = vi.fn().mockResolvedValue([{ id: 'cam1', label: 'front' }])
    start = vi.fn().mockResolvedValue(undefined)
    stop = vi.fn().mockResolvedValue(undefined)
    clear = vi.fn()
  },
}))

describe('QrScan', () => {
  beforeEach(() => {
    claimQrTag.mockReset()
  })

  it('posts a scanned token and reports success', async () => {
    claimQrTag.mockResolvedValue(undefined)
    const onTagged = vi.fn()
    const { rerender } = render(
      <QrScan
        gameId="game-1"
        onClose={() => undefined}
        onTagged={onTagged}
        onSignedOut={() => undefined}
        injectScan={null}
      />,
    )
    // Drive a scan without waiting on the camera callback.
    rerender(
      <QrScan
        gameId="game-1"
        onClose={() => undefined}
        onTagged={onTagged}
        onSignedOut={() => undefined}
        injectScan="scanned-token"
      />,
    )

    await waitFor(() => {
      expect(claimQrTag).toHaveBeenCalledWith({
        token: 'tok',
        gameId: 'game-1',
        qrToken: 'scanned-token',
      })
      expect(onTagged).toHaveBeenCalled()
    })
  })

  it('shows the server error when the tag is rejected', async () => {
    claimQrTag.mockRejectedValue(new ApiError('TOO_FAR', 'Too far to tag.', 409))
    render(
      <QrScan
        gameId="game-1"
        onClose={() => undefined}
        onTagged={() => undefined}
        onSignedOut={() => undefined}
        injectScan="scanned-token"
      />,
    )
    expect(await screen.findByText(/too far to tag/i)).toBeInTheDocument()
  })

  it('can close without scanning', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()
    render(
      <QrScan
        gameId="game-1"
        onClose={onClose}
        onTagged={() => undefined}
        onSignedOut={() => undefined}
        injectScan={null}
      />,
    )
    await user.click(screen.getByRole('button', { name: /close/i }))
    expect(onClose).toHaveBeenCalled()
  })
})
