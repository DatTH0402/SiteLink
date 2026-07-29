import api from './client'
import type { Site, SiteDryRunResult, ImportResult } from '@/types'

export const getSites = (params?: Record<string, unknown>) =>
  api.get<Site[]>('/api/v1/sites/', { params }).then((r) => r.data)

export const getSite = (id: number) =>
  api.get<Site>(`/api/v1/sites/${id}`).then((r) => r.data)

export const createSite = (data: Partial<Site>) =>
  api.post<Site>('/api/v1/sites/', data).then((r) => r.data)

export const updateSite = (id: number, data: Partial<Site>) =>
  api.put<Site>(`/api/v1/sites/${id}`, data).then((r) => r.data)

export const deleteSite = (id: number) =>
  api.delete(`/api/v1/sites/${id}`)

export const bulkDeleteSites = (ids: number[]) =>
  api.post<{ deleted: number; errors: string[] }>('/api/v1/sites/bulk-delete', { ids }).then((r) => r.data)

export const bulkUpdateSites = (ids: number[], changes: Record<string, unknown>) =>
  api.post<{ updated: number; errors: string[] }>('/api/v1/sites/bulk-update', { ids, changes }).then((r) => r.data)

export const dryRunSitesExcel = (file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<SiteDryRunResult>('/api/v1/sites/import-excel/dry-run', form)
    .then((r) => r.data)
}

export const importSitesExcel = (file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<ImportResult>('/api/v1/sites/import-excel', form)
    .then((r) => r.data)
}
