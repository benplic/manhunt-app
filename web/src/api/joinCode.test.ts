import { describe, expect, it } from 'vitest'
import { joinUrlForCode, parseJoinPayload, sanitizeJoinCode } from './joinCode'

describe('joinCode helpers', () => {
  it('sanitizes to the server alphabet', () => {
    expect(sanitizeJoinCode('ab1oil')).toBe('AB')
    expect(sanitizeJoinCode('c2tx8b')).toBe('C2TX8B')
  })

  it('builds and parses join URLs from either client', () => {
    expect(joinUrlForCode('C2TX8B', 'https://manhunt-app.pages.dev')).toBe(
      'https://manhunt-app.pages.dev/join/C2TX8B',
    )
    expect(parseJoinPayload('https://manhunt-app.pages.dev/join/c2tx8b')).toBe('C2TX8B')
    expect(parseJoinPayload('https://app.manhunt.ios/join/C2TX8B')).toBe('C2TX8B')
    expect(parseJoinPayload('https://manhunt-app.pages.dev/?join=c2tx8b')).toBe('C2TX8B')
    expect(parseJoinPayload('manhunt://join/C2TX8B')).toBe('C2TX8B')
    expect(parseJoinPayload('C2TX8B')).toBe('C2TX8B')
    expect(parseJoinPayload('http://localhost:5173/')).toBe('')
    // The hostname must not be alphabet-stripped into a fake code.
    expect(parseJoinPayload('https://manhunt-app.pages.dev/')).toBe('')
  })
})
