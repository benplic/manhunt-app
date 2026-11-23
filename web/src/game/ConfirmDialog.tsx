import './ConfirmDialog.css'

type Props = {
  title: string
  message?: string
  confirmLabel: string
  onConfirm: () => void
  onCancel: () => void
}

/** Yes/no gate for actions that are hard to undo, matching the iOS alerts. */
export function ConfirmDialog({ title, message, confirmLabel, onConfirm, onCancel }: Props) {
  return (
    <div className="confirm-scrim" role="presentation">
      <div className="confirm-dialog" role="dialog" aria-modal="true" aria-label={title}>
        <h2>{title}</h2>
        {message ? <p>{message}</p> : null}
        <div className="confirm-actions">
          <button type="button" className="confirm-danger" onClick={onConfirm}>
            {confirmLabel}
          </button>
          <button type="button" onClick={onCancel}>
            Cancel
          </button>
        </div>
      </div>
    </div>
  )
}
