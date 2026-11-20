import { Component, type ReactNode } from 'react'

type Props = {
  children: ReactNode
  onLeave: () => void
}

type State = {
  error: Error | null
}

/**
 * A render throw used to unmount the whole app and leave the dark page background.
 * Show the message and a way back to the lobby instead.
 */
export class HuntErrorBoundary extends Component<Props, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  render() {
    if (this.state.error) {
      return (
        <main className="home hunt-error">
          <h1>Couldn't open the hunt</h1>
          <p role="alert">{this.state.error.message}</p>
          <button type="button" className="secondary" onClick={this.props.onLeave}>
            Leave hunt
          </button>
        </main>
      )
    }
    return this.props.children
  }
}
