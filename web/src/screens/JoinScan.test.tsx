import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { JoinScan } from './JoinScan'

const cameraStart = vi.fn().mockResolvedValue(undefined)

vi.mock('html5-qrcode', () => ({
  Html5Qrcode: class {
    start = (...args: unknown[]) => cameraStart(...args)
    stop = vi.fn().mockResolvedValue(undefined)
    clear = vi.fn()
  },
}))

describe('JoinScan', () => {
  beforeEach(() => {
    cameraStart.mockReset()
    cameraStart.mockResolvedValue(undefined)
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
