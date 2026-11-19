import { useEffect, useRef, useState } from 'react'
import { apiBaseUrl } from './api/config'
import { leaveGame } from './api/games'
import { SessionExpiredError, withAuthRetry } from './api/session'
import type { PlayerView } from './api/types'
import { GameSocket, wsUrlForGame } from './api/ws'
import { loadSession } from './auth/storage'
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
  const [socketReady, setSocketReady] = useState(false)
  const socketRef = useRef<GameSocket | null>(null)

  function tearDownSocket() {
    socketRef.current?.disconnect()
    socketRef.current = null
    setSocketReady(false)
    setQrToken(null)
  }

  function clearGame() {
    tearDownSocket()
    setGameView(null)
  }

  function signOut() {
    tearDownSocket()
    setSocketNote(null)
    setGameView(null)
    setSignedIn(false)
  }

  // One long-lived socket per game so Lobby → LiveMap keeps lastSeq.
  useEffect(() => {
    if (!gameView) {
      tearDownSocket()
      setSocketNote(null)
      return
    }

    if (socketRef.current) {
      return
    }

    const socket = new GameSocket()
    socketRef.current = socket
    socket.onView = (next) => setGameView(next)
    socket.onQr = (token) => setQrToken(token)
    socket.onError = (err) => setSocketNote(err.message)
    socket.onRemoved = () => {
      tearDownSocket()
      setGameView(null)
      setSocketNote('You were removed from this hunt.')
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

  if (gameView && isLobby(gameView.phase)) {
    return (
      <Lobby
        view={gameView}
        onView={setGameView}
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
    return (
      <LiveMap
        view={gameView}
        socket={socketRef.current}
        qrToken={qrToken}
        note={socketNote}
        onView={setGameView}
        onLeave={() => void leaveCurrentGame()}
        onSignedOut={signOut}
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
