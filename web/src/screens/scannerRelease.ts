/**
 * html5-qrcode throws if stop() runs before start() reaches the scanning state,
 * and the camera stream from that start() is then left running.
 * Wait for start to settle, then stop. A rejected start has nothing to stop.
 */
export function releaseScanner(
  start: Promise<unknown>,
  stop: () => Promise<void>,
): Promise<void> {
  return start.then(
    () => stop(),
    () => undefined,
  )
}
