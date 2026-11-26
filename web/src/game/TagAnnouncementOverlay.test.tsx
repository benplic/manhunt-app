import { act, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { TagAnnouncementOverlay } from './TagAnnouncementOverlay'

describe('TagAnnouncementOverlay', () => {
  it('renders centered status copy in a noninteractive full-screen flash', () => {
    render(
      <TagAnnouncementOverlay
        announcement={{ seq: 4, text: 'Riley was tagged out of bounds!' }}
      />,
    )

    const status = screen.getByRole('status')
    expect(status).toHaveTextContent('Riley was tagged out of bounds!')
    expect(status).toHaveAttribute('aria-live', 'assertive')
    expect(status).toHaveClass('tag-announcement')
  })

  it('renders nothing without a current announcement', () => {
    const { container } = render(<TagAnnouncementOverlay announcement={null} />)
    expect(container).toBeEmptyDOMElement()
  })

  describe('fade out', () => {
    afterEach(() => {
      vi.useRealTimers()
    })

    it('keeps the last flash mounted while it fades, then removes it', () => {
      vi.useFakeTimers()
      const { rerender } = render(
        <TagAnnouncementOverlay announcement={{ seq: 9, text: 'Sam was tagged!' }} />,
      )
      rerender(<TagAnnouncementOverlay announcement={null} />)

      const fading = screen.getByRole('status')
      expect(fading).toHaveTextContent('Sam was tagged!')
      expect(fading).toHaveClass('tag-announcement--leaving')

      act(() => {
        vi.advanceTimersByTime(450)
      })
      expect(screen.queryByRole('status')).not.toBeInTheDocument()
    })
  })
})
