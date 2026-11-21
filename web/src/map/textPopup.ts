/**
 * Leaflet writes string popup content with innerHTML.
 * Player and reveal names come from the server, so the popup node
 * must carry them as text or a name can run script in the app origin.
 */
export function textPopup(label: string): HTMLElement {
  const node = document.createElement('span')
  node.textContent = label
  return node
}
