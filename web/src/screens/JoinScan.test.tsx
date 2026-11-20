import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { JoinScan } from './JoinScan'

const cameraStart = vi.fn().mockResolvedValue(undefined)
const scanners = vi.hoisted(() => [] as { stop: ReturnType<typeof vi.fn> }[])

vi.mock('html5-qrcode', () => ({
  Html5Qrcode: class {
    start = (...args: unknown[]) => cameraStart(...args)
    stop = vi.fn().mockResolvedValue(undefined)
    clear = vi.fn()
    constructor() {
      scanners.push(this)
    }
  },
}))

describe('JoinScan', () => {
  beforeEach(() => {
    cameraStart.mockReset()
    cameraStart.mockResolvedValue(undefined)
    scanners.length = 0
  })

  it('offers manual join entry when the camera is blocked', async () => {
    const user = userEvent.setup()
    const onCode = vi.fn()
    cameraStart.mockRejectedValueOnce(new Error('denied'))

    render(<JoinScan onClose={() => undefined} onCode={onCode} />)

    expect(await screen.findByText(/camera blocked/i)).toBeInTheDocument()
    expect(screen.getByPlaceholderText(/join code/i)).toBeInTheDocument()

    await user.type(screen.getByPlaceholderText(/join code/i), 'abcdef')
    await user.click(screen.getByRole('button', { name: /join with code/i }))

    await waitFor(() => {
      expect(onCode).toHaveBeenCalledWith('ABCDEF')
    })
  })

  it('stops the camera after start resolves when the screen closes mid-start', async () => {
    let resolveStart: () => void = () => undefined
    cameraStart.mockImplementation(
      () =>
        new Promise<void>((resolve) => {
          resolveStart = resolve
        }),
    )
    const { unmount } = render(<JoinScan onClose={() => undefined} onCode={() => undefined} />)
    unmount()
    expect(scanners[0]?.stop).not.toHaveBeenCalled()
    resolveStart()
    await waitFor(() => {
      expect(scanners[0]?.stop).toHaveBeenCalled()
    })
  })

  it('accepts an injected join payload without opening the camera', async () => {
    const onCode = vi.fn()
    render(
      <JoinScan
        onClose={() => undefined}
        onCode={onCode}
        injectScan="https://manhunt-app.pages.dev/?join=ZZZZZZ"
      />,
    )
    await waitFor(() => {
      expect(onCode).toHaveBeenCalledWith('ZZZZZZ')
    })
    expect(cameraStart).not.toHaveBeenCalled()
  })
})
