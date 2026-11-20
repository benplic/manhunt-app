import {
  getOrCreateInstallationId,
  saveHomeKey,
  saveSession,
} from '../auth/storage'
import { apiRequest } from './client'
import type { AuthOut } from './types'

function persistInstallationId(installationId: string): void {
  localStorage.setItem('manhunt.installationId', installationId)
}

export class TooYoungError extends Error {
  constructor() {
    super('Manhunt is not available for people under 13.')
    this.name = 'TooYoungError'
  }
}

export type SignInInput = {
  displayName: string
  age: number
  homeKey: string
  /** Tests inject a fixed id; production mints one in localStorage. */
  installationId?: string
}

export async function signInDev(input: SignInInput): Promise<AuthOut> {
  if (input.age < 13) {
    throw new TooYoungError()
  }

  const installationId = input.installationId ?? getOrCreateInstallationId()
  persistInstallationId(installationId)
  const auth = await apiRequest<AuthOut>('/v1/auth/dev', {
    method: 'POST',
    homeKey: input.homeKey,
    body: {
      display_name: input.displayName.trim(),
      installation_id: installationId,
      age: input.age,
    },
  })

  saveHomeKey(input.homeKey)
  saveSession({
    accessToken: auth.access_token,
    refreshToken: auth.refresh_token,
    displayName: auth.user.display_name,
    userId: auth.user.id,
  })
  return auth
}

/** Permanently deletes the signed-in user on this server. */
export async function deleteAccount(token: string): Promise<void> {
  await apiRequest<{ ok: boolean }>('/v1/me', {
    method: 'DELETE',
    token,
  })
}

export async function refreshAccessToken(refreshToken: string): Promise<AuthOut> {
  const auth = await apiRequest<AuthOut>('/v1/auth/refresh', {
    method: 'POST',
    body: { refresh_token: refreshToken },
  })
  saveSession({
    accessToken: auth.access_token,
    refreshToken: auth.refresh_token,
    displayName: auth.user.display_name,
    userId: auth.user.id,
  })
  return auth
}
