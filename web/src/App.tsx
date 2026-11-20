import { useEffect, useRef, useState } from 'react'
import { apiBaseUrl } from './api/config'
import { fetchGameView, leaveGame } from './api/games'
import { SessionExpiredError, withAuthRetry } from './api/session'
import type { PlayerView } from './api/types'
import { GameSocket, wsUrlForGame } from './api/ws'
import { clearSession, loadSession } from './auth/storage'
import { HuntErrorBoundary } from './game/HuntErrorBoundary'
import { closedGameMessage, isClosedGameError } from './game/rejoin'
import { clearActiveGame, loadActiveGameId, rememberActiveGame } from './game/resume'
import {
  ackSafetyDisclaimer,
  needsSafetyDisclaimer,
  SAFETY_DISCLAIMER_COPY,
} from './game/safetyDisclaimer'
import { Home } from './screens/Home'
import { LiveMap } from './screens/LiveMap'
import { Lobby } from './screens/Lobby'
import { Result } from './screens/Result'
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
  const [qrToken, setQrToken] = useState<string | null>(null)
  const [socketNote, setSocketNote] = useState<string | null>(null)
  const [homeNote, setHomeNote] = useState<string | null>(null)
  const [socketReady, setSocketReady] = useState(false)
  const [resuming, setResuming] = useState(false)
  const socketRef = useRef<GameSocket | null>(null)
  /** Bumps when the player cancels rejoin so an in-flight fetch cannot land. */
  const rejoinEpochRef = useRef(0)
  const [safetyGateOpen, setSafetyGateOpen] = useState(false)

  function tearDownSocket() {
    socketRef.current?.disconnect()
    socketRef.current = null
    setSocketReady(false)
    setQrToken(null)
  }

  useEffect(() => {
    if (gameView && isLive(gameView.phase) && needsSafetyDisclaimer()) {
      setSafetyGateOpen(true)
    }
  }, [gameView?.game_id, gameView?.phase])

  function applyView(next: PlayerView) {
    rememberActiveGame(next.game_id)
    setHomeNote(null)
    // Result only needs the last view; stop the socket as soon as the hunt ends.
    if (next.phase === 'ended') {
      tearDownSocket()
    }
    setGameView(next)
  }

  function clearGame() {
    tearDownSocket()
    clearActiveGame()
    setGameView(null)
  }

  function signOut() {
    rejoinEpochRef.current += 1
    tearDownSocket()
    clearActiveGame()
    clearSession()
    setSocketNote(null)
    setHomeNote(null)
    setResuming(false)
    setGameView(null)
    setSignedIn(false)
  }

  function cancelRejoin() {
    rejoinEpochRef.current += 1
    clearActiveGame()
    setResuming(false)
    setHomeNote('Rejoin cancelled.')
  }

  // Rejoin the open game after a refresh. Do not put `resuming` in the deps —
  // that cancelled the in-flight fetch and left a blank "Rejoining…" screen.
  useEffect(() => {
    if (!signedIn || gameView) {
      return
    }
    const gameId = loadActiveGameId()
    if (!gameId) {
      return
    }
    const epoch = rejoinEpochRef.current
    setResuming(true)
    setHomeNote(null)
    void withAuthRetry((token) => fetchGameView({ token, gameId }))
      .then((view) => {
        if (epoch !== rejoinEpochRef.current) {
          return
        }
        applyView(view)
      })
      .catch((err) => {
        if (epoch !== rejoinEpochRef.current) {
          return
        }
        clearActiveGame()
        if (err instanceof SessionExpiredError) {
          signOut()
          return
        }
        if (isClosedGameError(err)) {
          setHomeNote(closedGameMessage(err))
          return
        }
        setHomeNote(closedGameMessage(err))
      })
      .finally(() => {
        if (epoch === rejoinEpochRef.current) {
          setResuming(false)
        }
      })
  }, [signedIn, gameView])

  // One long-lived socket per game id. Phase changes (head_start → active) must
  // not tear down or flash the "Connecting…" shell — that looked like a black page.
  useEffect(() => {
    if (!gameView) {
      tearDownSocket()
      setSocketNote(null)
      return
    }
    if (gameView.phase === 'ended') {
      return
    }
    if (socketRef.current) {
      return
    }

    const socket = new GameSocket()
    socketRef.current = socket
    socket.onView = (next) => applyView(next)
    socket.onQr = (token) => setQrToken(token)
    socket.onError = (err) => {
      // Too-fast GPS jumps are expected on the web; do not spam the banner.
      if (err.message.toLowerCase().includes('too fast')) {
        return
      }
      setSocketNote(err.message)
    }
    socket.onRemoved = () => {
      tearDownSocket()
      clearActiveGame()
      setGameView(null)
      setHomeNote('You were removed from this hunt.')
    }
    socket.connect({
      url: wsUrlForGame(apiBaseUrl(), gameView.game_id),
      getToken: () => loadSession()?.accessToken,
      lastSeq: socket.lastSeq,
    })
    setSocketReady(true)
  }, [gameView?.game_id])

  async function leaveCurrentGame() {
    if (!gameView) {
      return
    }
    const gameId = gameView.game_id
    tearDownSocket()
    clearActiveGame()
    try {
      await withAuthRetry((token) => leaveGame({ token, gameId }))
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

  if (resuming && !gameView) {
    return (
      <main className="home">
        <p>Rejoining the hunt…</p>
        <button type="button" className="secondary" onClick={cancelRejoin}>
          Cancel rejoin
        </button>
      </main>
    )
  }

  if (gameView && isLobby(gameView.phase)) {
    return (
      <Lobby
        view={gameView}
        onView={applyView}
        onLeave={() => void leaveCurrentGame()}
        onSignedOut={signOut}
        socketNote={socketNote}
      />
    )
  }

  if (gameView && gameView.phase === 'ended') {
    return (
      <Result
        view={gameView}
        onDone={() => {
          clearGame()
        }}
        onRematch={(next) => {
          tearDownSocket()
          applyView(next)
        }}
        onSignedOut={signOut}
      />
    )
  }

  if (gameView && isLive(gameView.phase)) {
    if (!socketReady || !socketRef.current) {
      return (
        <main className="home">
          <p>Connecting to the hunt…</p>
        </main>
      )
    }
    // Keep LiveMap mounted under the safety gate. Replacing it with a full-page
    // gate then remounting Leaflet after Continue left a black map on phones.
    return (
      <HuntErrorBoundary key={gameView.game_id} onLeave={() => void leaveCurrentGame()}>
        <LiveMap
          view={gameView}
          socket={socketRef.current}
          qrToken={qrToken}
          note={socketNote}
          onView={applyView}
          onLeave={() => void leaveCurrentGame()}
          onSignedOut={signOut}
        />
        {safetyGateOpen ? (
          <div className="safety-gate" role="dialog" aria-modal="true" aria-labelledby="safety-gate-title">
            <div className="safety-gate__card">
              <h1 id="safety-gate-title">Play safely</h1>
              <p>{SAFETY_DISCLAIMER_COPY}</p>
              <button
                type="button"
                onClick={() => {
                  ackSafetyDisclaimer()
                  setSafetyGateOpen(false)
                  // Leaflet may have initialized under a covered frame; refresh size.
                  window.setTimeout(() => window.dispatchEvent(new Event('resize')), 0)
                }}
              >
                Continue
              </button>
            </div>
          </div>
        ) : null}
      </HuntErrorBoundary>
    )
  }

  return (
    <Home
      onSignedOut={signOut}
      onEnteredGame={(view) => applyView(view)}
      bannerNote={homeNote}
      onClearBanner={() => setHomeNote(null)}
    />
  )
}

export default App
