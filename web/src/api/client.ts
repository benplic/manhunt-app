import { apiBaseUrl } from './config'
import type { ApiErrorBody } from './types'

export class ApiError extends Error {
  readonly code: string
  readonly status: number

  constructor(code: string, message: string, status: number) {
    super(message)
    this.name = 'ApiError'
    this.code = code
    this.status = status
  }
}

export type RequestOptions = {
  method?: string
  body?: unknown
  token?: string | null
  homeKey?: string | null
}

export async function apiRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
  }
  if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json'
  }
  if (options.token) {
    headers.Authorization = `Bearer ${options.token}`
  }
  if (options.homeKey) {
    headers['X-Manhunt-Dev-Secret'] = options.homeKey
  }

  const response = await fetch(`${apiBaseUrl()}${path}`, {
    method: options.method ?? (options.body !== undefined ? 'POST' : 'GET'),
    headers,
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  })

  if (!response.ok) {
    let code = 'INTERNAL'
    let message = `HTTP ${response.status}`
    try {
      const payload = (await response.json()) as ApiErrorBody
      code = payload.error?.code ?? code
      message = payload.error?.message ?? message
    } catch {
      // TODO: surface non-JSON failure bodies when the proxy returns HTML.
    }
    throw new ApiError(code, message, response.status)
  }

  if (response.status === 204) {
    return undefined as T
  }
  return (await response.json()) as T
}
