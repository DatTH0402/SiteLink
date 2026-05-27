import axios from 'axios'

// Detect current host/port so it works on any port
const api = axios.create({ baseURL: window.location.origin })

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('sl_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

api.interceptors.response.use(
  (r) => r,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('sl_token')
      window.location.href = '/login'
    }
    return Promise.reject(err)
  },
)

export default api