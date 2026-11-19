import { useState } from 'react'
import { leaveGame } from './api/games'
import { SessionExpiredError, withAuthRetry } from './api/session'
import type { PlayerView } from './api/types'
import { loadSession } from './auth/storage'
import { Home } from './screens/Home'
import { LiveMap } from './screens/LiveMap'
import { Lobby } from './screens/Lobby'
import { SignIn } from './screens/SignIn'
import './App.css'

function isLobby(phase: string): boolean {
  return phase === 'lobby'
}

function isLive(phase: string): boolean {
  return phase === 'head_start' || phase === 'active' || phase === 'paused'
}

function App() {
  const [signedIn, setSignedIn] = useState(() => loadSession() !== null)
  const [gameView, setGameView] = useState<PlayerView | null>(null)

  function signOut() {
    setGameView(null)
    setSignedIn(false)
  }

  async function leaveCurrentGame() {
    if (!gameView) {
      return
    }
    try {
      await withAuthRetry((token) => leaveGame({ token, gameId: gameView.game_id }))
    } catch (err) {
      if (err instanceof SessionExpiredError) {
        signOut()
        return
      }
      // Still leave the local UI if the server already closed the seat.
    }
    setGameView(null)
  }

  if (!signedIn) {
    return <SignIn onSignedIn={() => setSignedIn(true)} />
  }

  if (gameView && isLobby(gameView.phase)) {
    return (
      <Lobby
        view={gameView}
        onView={setGameView}
        onLeave={() => void leaveCurrentGame()}
        onSignedOut={signOut}
      />
    )
  }

  if (gameView && (isLive(gameView.phase) || gameView.phase === 'ended')) {
    return (
      <LiveMap
        view={gameView}
        onView={setGameView}
        onLeave={() => void leaveCurrentGame()}
      />
    )
  }

  return (
    <Home
      onSignedOut={signOut}
      onEnteredGame={(view) => setGameView(view)}
    />
  )
}

export default App
