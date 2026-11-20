import { describe, expect, it } from 'vitest'
import { newRevealIds } from './pingFlash'

describe('newRevealIds', () => {
  it('detects newly added reveal ids', () => {
    const prev = [{ reveal_id: 'a' }]
    const next = [{ reveal_id: 'a' }, { reveal_id: 'b' }]
    expect(newRevealIds(prev, next)).toEqual(['b'])
  })
})