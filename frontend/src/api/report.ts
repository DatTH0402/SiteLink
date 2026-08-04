import api from './client'

export const getReport = (params?: Record<string, unknown>) =>
  api.get('/api/v1/report/summary', { params }).then((r) => r.data)

export const getReportByProvince = () =>
  api.get('/api/v1/report/by-province').then((r) => r.data)

export const getReportCellsByProvince = (tech: '3g' | '4g' | '5g') =>
  api
    .get('/api/v1/report/cells-by-province', { params: { tech } })
    .then((r) => r.data)

export const getAuditLogs = (params?: Record<string, unknown>) =>
  api.get('/api/v1/audit/', { params }).then((r) => r.data)

export const getDropdown = (category: string) =>
  api.get(`/api/v1/dropdowns/general/${category}`).then((r) => r.data)

export const getVendors = () =>
  api.get('/api/v1/dropdowns/vendor').then((r) => r.data)

export const getTinhXaPhuong = (tinh?: string) => {
  const params = tinh ? { tinh } : {}
  return api.get('/api/v1/dropdowns/tinh-xa-phuong', { params }).then((r) => r.data)
}

export const getTinhList = () =>
  api.get('/api/v1/dropdowns/tinh-list').then((r) => r.data)

export const getAntennaList = () =>
  api.get('/api/v1/dropdowns/antenna').then((r) => r.data)

/**
 * Get ward (phường/xã) list for a given province.
 * Returns unique ten_phuong_xa values sorted alphabetically.
 */
export const getPhuongXaList = (tinh: string): Promise<string[]> =>
  api
    .get('/api/v1/dropdowns/tinh-xa-phuong', { params: { tinh } })
    .then((r) =>
      [...new Set<string>((r.data as { ten_phuong_xa: string }[]).map((x) => x.ten_phuong_xa))]
        .filter(Boolean)
        .sort()
    )
