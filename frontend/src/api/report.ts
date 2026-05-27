import api from './client'

export const getReport = (params?: Record<string, unknown>) =>
  api.get('/api/v1/report/summary', { params }).then((r) => r.data)

export const getAuditLogs = (params?: Record<string, unknown>) =>
  api.get('/api/v1/audit/', { params }).then((r) => r.data)

export const getDropdown = (category: string) =>
  api.get(`/api/v1/dropdowns/general/${category}`).then((r) => r.data)

export const getVendors = () =>
  api.get('/api/v1/dropdowns/vendor').then((r) => r.data)

export const getTinhXaPhuong = () =>
  api.get('/api/v1/dropdowns/tinh-xa-phuong').then((r) => r.data)
