import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { QrShow } from './QrShow'

vi.mock('qrcode', () => ({
  default: {
    toDataURL: vi.fn().mockResolvedValue('data:image/png;base64,qr'),
  },
}))

describe('QrShow', () => {
  it('renders a QR image for the token', async () => {
    render(<QrShow token="qr-secret" onClose={() => undefined} />)
    const img = await screen.findByRole('img', { name: /tag qr/i })
    await waitFor(() => {
      expect(img).toHaveAttribute('src', 'data:image/png;base64,qr')
    })
  })
})
