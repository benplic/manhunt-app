import { useState } from 'react'
import type { PlayerView } from './api/types'
import { loadSession } from './auth/storage'
import { Home } from './screens/Home'
import { SignIn } from './screens/SignIn'
import './App.css'

function App() {
  const [signedIn, setSignedIn] = useState(() => loadSession() !== null)
  // Kept for the lobby/live slice; Home still shows the join code for now.
  const [, setGameView] = useState<PlayerView | null>(null)

  if (!signedIn) {
    return <SignIn onSignedIn={() => setSignedIn(true)} />
  }

  return (
    <Home
      onSignedOut={() => {
        setGameView(null)
        setSignedIn(false)
      }}
      onEnteredGame={(view) => setGameView(view)}
    />
  )
}

export default App
