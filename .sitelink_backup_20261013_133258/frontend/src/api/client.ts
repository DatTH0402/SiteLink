import axios from 'axios'

const api = axios.create({
  baseURL: window.location.origin,
  paramsSerializer: {
    // Serialize arrays as repeated params: tinh=HN&tinh=HCM
    // (not tinh[]=HN&tinh[]=HCM which FastAPI rejects)
    serialize: (params) => {
      const parts: string[] = []
      Object.entries(params).forEach(([key, value]) => {
        if (value === undefined || value === null) return
        if (Array.isArray(value)) {
          value.forEach((v) => {
            if (v !== undefined && v !== null && v !== '')
              parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(v)}`)
          })
        } else {
          parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`)
        }
      })
      return parts.join('&')
    },
  },
})

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
