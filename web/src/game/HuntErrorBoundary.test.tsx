import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { HuntErrorBoundary } from './HuntErrorBoundary'

function Boom(): never {
  throw new Error('Objects are not valid as a React child')
}

describe('HuntErrorBoundary', () => {
  it('shows the failure and a way out instead of a blank page', async () => {
    const user = userEvent.setup()
    const onLeave = vi.fn()
    const spy = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    render(
      <HuntErrorBoundary onLeave={onLeave}>
        <Boom />
      </HuntErrorBoundary>,
    )
    expect(screen.getByRole('alert')).toHaveTextContent(/not valid as a react child/i)
    await user.click(screen.getByRole('button', { name: /leave hunt/i }))
    expect(onLeave).toHaveBeenCalled()
    spy.mockRestore()
  })
})
