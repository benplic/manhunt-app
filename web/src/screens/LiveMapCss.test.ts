import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

// vitest runs from web/. import.meta.url is not a file URL under jsdom.
const css = readFileSync(resolve(process.cwd(), 'src/screens/LiveMap.css'), 'utf8')

function rule(selector: string): string {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const match = new RegExp(`(?:^|\\n)${escaped}\\s*\\{([^}]*)\\}`).exec(css)
  expect(match, `missing CSS rule for ${selector}`).not.toBeNull()
  return match?.[1] ?? ''
}

// jsdom has no layout, so these pin the CSS that keeps the alert from resizing the map.
describe('LiveMap alert CSS', () => {
  it('overlays .banners instead of laying it out in the column', () => {
    const body = rule('.live-map .banners')
    expect(body).toMatch(/position:\s*absolute/)
    expect(body).toMatch(/pointer-events:\s*none/)
  })

  it('anchors the overlay in a zero-height box', () => {
    const body = rule('.live-map .alert-anchor')
    expect(body).toMatch(/height:\s*0/)
    expect(body).toMatch(/position:\s*relative/)
  })

  it('turns the fade off for reduced motion', () => {
    expect(css).toMatch(
      /@media \(prefers-reduced-motion: reduce\)\s*\{\s*\.live-map \.banner\s*\{\s*animation:\s*none/,
    )
  })

  it('no longer puts banners in the flex column group', () => {
    expect(css).not.toMatch(/\.live-map \.hud,\s*\n\.live-map \.banners/)
  })
})
