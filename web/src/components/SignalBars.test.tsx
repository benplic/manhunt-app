import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { SocketHealth } from '../api/ws'
import { SignalBars } from './SignalBars'

const NOW = 1_000_000

function health(overrides: Partial<SocketHealth> = {}): SocketHealth {
  return { connected: true, failureStreak: 0, lastMessageAt: NOW - 1000, ...overrides }
}

describe('SignalBars', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it('is a button with a text label for assistive tech', () => {
    render(<SignalBars getHealth={() => health()} onExplain={vi.fn()} now={() => NOW} />)
    expect(screen.getByRole('button', { name: 'Connection: good' })).toBeInTheDocument()
  })

  it('fills the bars to match the state and marks the worst states with a flag', () => {
    const { container, rerender } = render(
      <SignalBars getHealth={() => health()} onExplain={vi.fn()} now={() => NOW} />,
    )
    expect(container.querySelectorAll('.signal-bars__bar--on')).toHaveLength(4)
    expect(container.querySelector('.signal-bars__flag')).toBeNull()

    rerender(
      <SignalBars
        getHealth={() => health({ connected: false, failureStreak: 3 })}
        onExplain={vi.fn()}
        now={() => NOW}
      />,
    )
    expect(container.querySelectorAll('.signal-bars__bar--on')).toHaveLength(1)
    expect(container.querySelector('.signal-bars__flag')).not.toBeNull()
    expect(screen.getByRole('button', { name: 'Connection: unstable' })).toBeInTheDocument()
  })

  it('drops to 3 bars when the last message is older than 5 seconds', () => {
    render(
      <SignalBars
        getHealth={() => health({ lastMessageAt: NOW - 6000 })}
        onExplain={vi.fn()}
        now={() => NOW}
      />,
    )
    expect(screen.getByRole('button', { name: 'Connection: slow' })).toBeInTheDocument()
  })

  it('shows 0 bars when the browser is offline', () => {
    const spy = vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false)
    render(
      <SignalBars
        getHealth={() => health({ connected: false, failureStreak: 1 })}
        onExplain={vi.fn()}
        now={() => NOW}
      />,
    )
    expect(screen.getByRole('button', { name: 'Connection: down' })).toBeInTheDocument()
    spy.mockRestore()
  })

  it('renders nothing when there is no socket health', () => {
    const { container } = render(
      <SignalBars getHealth={() => null} onExplain={vi.fn()} now={() => NOW} />,
    )
    expect(container).toBeEmptyDOMElement()
  })

  it('hands a short explanation with the last message age to the caller on tap', async () => {
    const onExplain = vi.fn()
    render(<SignalBars getHealth={() => health()} onExplain={onExplain} now={() => NOW} />)
    await userEvent.click(screen.getByRole('button', { name: 'Connection: good' }))
    expect(onExplain).toHaveBeenCalledWith('Connected. Updates are arriving. Last update 1s ago.')
  })

  it('re-reads the socket every second so the 5 second window moves on its own', () => {
    vi.useFakeTimers()
    let clock = NOW
    render(
      <SignalBars
        getHealth={() => health({ lastMessageAt: NOW })}
        onExplain={vi.fn()}
        now={() => clock}
      />,
    )
    expect(screen.getByRole('button', { name: 'Connection: good' })).toBeInTheDocument()
    clock = NOW + 6000
    act(() => {
      vi.advanceTimersByTime(1000)
    })
    expect(screen.getByRole('button', { name: 'Connection: slow' })).toBeInTheDocument()
  })
})
