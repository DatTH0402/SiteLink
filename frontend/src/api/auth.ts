import api from './client'
import type { User } from '@/types'

export const login = (username: string, password: string) => {
  const form = new URLSearchParams()
  form.append('username', username)
  form.append('password', password)
  return api
    .post<{ access_token: string; token_type: string }>(
      '/api/v1/auth/login',
      form,
      { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } },
    )
    .then((r) => r.data)
}

export const getMe = () =>
  api.get<User>('/api/v1/auth/me').then((r) => r.data)

/**
 * Build the callback URL dynamically from the current browser location.
 * Works for localhost:8081, 10.24.15.169:8081, mlmt.mobifone.vn, etc.
 */
export function buildCallbackUrl(): string {
  const { protocol, host } = window.location
  return `${protocol}//${host}/sitelink/sso/callback`
}

/**
 * Get Keycloak authorization URL.
 * Always passes the dynamic redirect_uri so the backend uses the correct host.
 */
export const getSsoLoginUrl = () => {
  const redirectUri = buildCallbackUrl()
  return api
    .get<{ url: string; state: string; sso_enabled: boolean; redirect_uri: string }>(
      `/api/v1/auth/sso/login-url?redirect_uri=${encodeURIComponent(redirectUri)}`
    )
    .then((r) => r.data)
}

/**
 * Exchange authorization code for our JWT.
 * MUST pass the same redirect_uri that was used to get the code.
 */
export const ssoCallback = (code: string, redirectUri?: string) =>
  api
    .post<{ access_token: string; token_type: string }>(
      '/api/v1/auth/sso/callback',
      { code, redirect_uri: redirectUri ?? buildCallbackUrl() }
    )
    .then((r) => r.data)

/** Logout from SSO server */
export const ssoLogout = (id_token?: string) =>
  api.post('/api/v1/auth/sso/logout', { id_token }).then((r) => r.data)

/** Get SSO config */
export const getSsoConfig = () =>
  api
    .get<{ sso_enabled: boolean; client_id: string; redirect_uri: string }>(
      '/api/v1/auth/sso/config'
    )
    .then((r) => r.data)
