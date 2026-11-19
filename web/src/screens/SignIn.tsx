import { useState } from 'react'
import type { FormEvent } from 'react'
import { signInDev, TooYoungError } from '../api/auth'
import { ApiError } from '../api/client'
import { PRIVACY_URL, SUPPORT_EMAIL } from '../api/legal'
import { loadHomeKey } from '../auth/storage'
import './SignIn.css'

type Props = {
  onSignedIn: () => void
}

export function SignIn({ onSignedIn }: Props) {
  const [displayName, setDisplayName] = useState('')
  const [age, setAge] = useState('')
  const [homeKey, setHomeKey] = useState(() => loadHomeKey() ?? '')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function onSubmit(event: FormEvent) {
    event.preventDefault()
    setError(null)

    const ageYears = Number.parseInt(age, 10)
    if (!Number.isFinite(ageYears)) {
      setError('Enter your age as a number.')
      return
    }
    if (ageYears < 13) {
      setError('Manhunt is not available for people under 13.')
      return
    }
    if (!displayName.trim()) {
      setError('Enter a display name.')
      return
    }
    if (!homeKey.trim()) {
      setError('Enter the home key.')
      return
    }

    setBusy(true)
    try {
      await signInDev({
        displayName: displayName.trim(),
        age: ageYears,
        homeKey: homeKey.trim(),
      })
      onSignedIn()
    } catch (err) {
      if (err instanceof TooYoungError) {
        setError(err.message)
      } else if (err instanceof ApiError) {
        setError(err.message)
      } else {
        setError('Could not reach the hunt server.')
      }
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="sign-in">
      <h1>Manhunt</h1>
      <p className="lede">Play with friends in the browser. No Apple account required.</p>
      <form onSubmit={onSubmit}>
        <label>
          Display name
          <input
            name="displayName"
            autoComplete="nickname"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            maxLength={40}
            required
          />
        </label>
        <label>
          Age
          <input
            name="age"
            inputMode="numeric"
            value={age}
            onChange={(e) => setAge(e.target.value)}
            required
          />
        </label>
        <label>
          Home key
          <input
            name="homeKey"
            type="password"
            autoComplete="off"
            value={homeKey}
            onChange={(e) => setHomeKey(e.target.value)}
            required
          />
        </label>
        {error ? <p className="error" role="alert">{error}</p> : null}
        <button type="submit" disabled={busy}>
          {busy ? 'Signing in…' : 'Play'}
        </button>
      </form>
      <p className="footer-links">
        <a href={PRIVACY_URL} target="_blank" rel="noreferrer">
          Privacy policy
        </a>
        {' · '}
        <a href={`mailto:${SUPPORT_EMAIL}`}>Support</a>
      </p>
    </main>
  )
}
