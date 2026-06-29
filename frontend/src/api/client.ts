import axios from 'axios'

const api = axios.create({ baseURL: window.location.origin })

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('sl_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

api.interceptors.response.use(
  (r) => r,
  (err) => {
    // Only auto-logout on 401 Unauthorized, not on other errors
    if (err.response?.status === 401) {
      localStorage.removeItem('sl_token')
      window.location.href = '/login'
    }
    // Always reject so callers can handle the error themselves
    return Promise.reject(err)
  },
)

export default api
