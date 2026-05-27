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
