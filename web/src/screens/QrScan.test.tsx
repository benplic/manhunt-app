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

const cameraStart = vi.fn().mockResolvedValue(undefined)
const scanners = vi.hoisted(() => [] as { stop: ReturnType<typeof vi.fn> }[])

vi.mock('html5-qrcode', () => ({
  Html5Qrcode: class {
    static getCameras = vi.fn().mockResolvedValue([{ id: 'cam1', label: 'front' }])
    start = (...args: unknown[]) => cameraStart(...args)
    stop = vi.fn().mockResolvedValue(undefined)
    clear = vi.fn()
    constructor() {
      scanners.push(this)
    }
  },
}))

describe('QrScan', () => {
  beforeEach(() => {
    claimQrTag.mockReset()
    cameraStart.mockReset()
    cameraStart.mockResolvedValue(undefined)
    scanners.length = 0
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
        accuracyM={5}
        injectScan={null}
      />,
    )
    rerender(
      <QrScan
        gameId="game-1"
        onClose={() => undefined}
        onTagged={onTagged}
        onSignedOut={() => undefined}
        accuracyM={5}
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

  it('shows the server error when the tag is rejected and offers retry', async () => {
    claimQrTag.mockRejectedValue(
      new ApiError('NOT_IN_PAIRING_RANGE', 'Get closer. GPS says you are too far to tag.', 409),
    )
    render(
      <QrScan
        gameId="game-1"
        onClose={() => undefined}
        onTagged={() => undefined}
        onSignedOut={() => undefined}
        accuracyM={5}
        injectScan="scanned-token"
      />,
    )
    expect(await screen.findByText(/get closer/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /try again/i })).toBeInTheDocument()
  })

  it('holds a scan when GPS is fuzzy instead of posting', async () => {
    render(
      <QrScan
        gameId="game-1"
        onClose={() => undefined}
        onTagged={() => undefined}
        onSignedOut={() => undefined}
        accuracyM={45}
        injectScan="scanned-token"
      />,
    )
    expect(await screen.findByText(/too fuzzy/i)).toBeInTheDocument()
    expect(claimQrTag).not.toHaveBeenCalled()
  })

  it('expands manual entry when the camera is blocked', async () => {
    cameraStart.mockRejectedValueOnce(new Error('denied'))
    render(
      <QrScan
        gameId="game-1"
        onClose={() => undefined}
        onTagged={() => undefined}
        onSignedOut={() => undefined}
        accuracyM={5}
        injectScan={null}
      />,
    )
    expect(await screen.findByText(/camera blocked/i)).toBeInTheDocument()
    expect(screen.getByPlaceholderText(/paste or type/i)).toBeInTheDocument()
  })

  it('uses dark-theme scan chrome so controls stay visible on the live overlay', () => {
    const { container } = render(
      <QrScan
        gameId="game-1"
        onClose={() => undefined}
        onTagged={() => undefined}
        onSignedOut={() => undefined}
        accuracyM={5}
        injectScan={null}
      />,
    )
    expect(container.querySelector('main.qr-scan')).toBeTruthy()
    // Light-theme leftovers (#555 / #1a1a1a-on-dark) made the scanner look blank.
    expect(container.querySelector('main.qr-scan--dark')).toBeTruthy()
  })

  it('stops the camera after start resolves when the screen closes mid-start', async () => {
    let resolveStart: () => void = () => undefined
    cameraStart.mockImplementation(
      () =>
        new Promise<void>((resolve) => {
          resolveStart = resolve
        }),
    )
    const { unmount } = render(
      <QrScan
        gameId="game-1"
        onClose={() => undefined}
        onTagged={() => undefined}
        onSignedOut={() => undefined}
        accuracyM={5}
        injectScan={null}
      />,
    )
    unmount()
    expect(scanners[0]?.stop).not.toHaveBeenCalled()
    resolveStart()
    await waitFor(() => {
      expect(scanners[0]?.stop).toHaveBeenCalled()
    })
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
        accuracyM={5}
        injectScan={null}
      />,
    )
    await user.click(screen.getByRole('button', { name: /close/i }))
    expect(onClose).toHaveBeenCalled()
  })
})
