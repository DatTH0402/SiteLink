import { create } from 'zustand'
import type { User } from '@/types'

interface AuthState {
  user:     User | null
  token:    string | null
  idToken:  string | null   // for SSO logout
  setAuth:  (user: User, token: string, idToken?: string) => void
  logout:   () => void
}

export const useAuthStore = create<AuthState>((set) => ({
  user:    null,
  token:   localStorage.getItem('sl_token'),
  idToken: localStorage.getItem('sl_id_token'),
  setAuth: (user, token, idToken) => {
    localStorage.setItem('sl_token', token)
    if (idToken) localStorage.setItem('sl_id_token', idToken)
    set({ user, token, idToken: idToken ?? null })
  },
  logout: () => {
    localStorage.removeItem('sl_token')
    localStorage.removeItem('sl_id_token')
    set({ user: null, token: null, idToken: null })
  },
}))
