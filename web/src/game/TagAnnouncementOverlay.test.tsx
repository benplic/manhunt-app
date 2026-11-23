import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
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
})
