import { create } from 'zustand'
import type { User } from '@/types'

interface AuthState {
  user: User | null
  token: string | null
  setAuth: (user: User, token: string) => void
  logout: () => void
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  token: localStorage.getItem('sl_token'),
  setAuth: (user, token) => {
    localStorage.setItem('sl_token', token)
    set({ user, token })
  },
  logout: () => {
    localStorage.removeItem('sl_token')
    set({ user: null, token: null })
  },
}))
