import type { PlayerView } from '../api/types'
import './Result.css'

type Props = {
  view: PlayerView
  onDone: () => void
}

export function Result({ view, onDone }: Props) {
  const result = view.result
  return (
    <main className="result">
      <h1>Hunt over</h1>
      {result ? (
        <>
          <p className="winner">
            Winner: <strong>{result.winner}</strong>
          </p>
          <p className="reason">{result.reason}</p>
        </>
      ) : (
        <p>No result payload from the server.</p>
      )}
      <p className="code">Code was {view.join_code}</p>
      <button type="button" onClick={onDone}>
        Done
      </button>
    </main>
  )
}
