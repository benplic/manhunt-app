import { describe, expect, it } from 'vitest'
import { leafletIconUrlsForTests } from './leafletIcons'

describe('leaflet default icons', () => {
  it('resolves bundled marker URLs (not relative marker-icon.png)', () => {
    const urls = leafletIconUrlsForTests()
    expect(urls.iconUrl).toMatch(/marker-icon/)
    expect(urls.iconUrl).not.toBe('marker-icon.png')
    expect(urls.shadowUrl).toMatch(/marker-shadow/)
    expect(urls.shadowUrl).not.toBe('marker-shadow.png')
  })
})
