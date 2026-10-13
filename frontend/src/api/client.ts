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

// The app is served under /sitelink/ (Vite base + BrowserRouter basename).
const LOGIN_PATH = '/sitelink/login'

api.interceptors.response.use(
  (r) => r,
  (err) => {
    const url: string = err?.config?.url ?? ''
    const isAuthCall = url.includes('/auth/login') || url.includes('/auth/sso')
    // Expired / invalid token -> back to the login page (but never for the login calls themselves)
    if (err?.response?.status === 401 && !isAuthCall) {
      localStorage.removeItem('sl_token')
      localStorage.removeItem('sl_id_token')
      if (!window.location.pathname.startsWith(LOGIN_PATH)) {
        window.location.href = LOGIN_PATH
      }
    }
    return Promise.reject(err)
  },
)

export default api
