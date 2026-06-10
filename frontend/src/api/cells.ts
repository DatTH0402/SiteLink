import api from './client'
import type { Cell3G, Cell4G, Cell5G } from '@/types'

export interface CellImportResult {
  created: number
  updated: number
  sites_auto_created: number
  errors: string[]
}

export interface SiteImportResult {
  created: number
  updated: number
  errors: string[]
}

function makeCellApi<T>(tech: string) {
  return {
    list: (params?: Record<string, unknown>) =>
      api.get<T[]>(`/api/v1/cells-${tech}/`, { params }).then((r) => r.data),

    get: (id: number) =>
      api.get<T>(`/api/v1/cells-${tech}/${id}`).then((r) => r.data),

    create: (data: Partial<T>) =>
      api.post<T>(`/api/v1/cells-${tech}/`, data).then((r) => r.data),

    update: (id: number, data: Partial<T>) =>
      api.put<T>(`/api/v1/cells-${tech}/${id}`, data).then((r) => r.data),

    remove: (id: number) =>
      api.delete(`/api/v1/cells-${tech}/${id}`),

    importExcel: (file: File) => {
      const form = new FormData()
      form.append('file', file)
      return api
        .post<CellImportResult>(`/api/v1/cells-${tech}/import-excel`, form)
        .then((r) => r.data)
    },
  }
}

export const cells3gApi = makeCellApi<Cell3G>('3g')
export const cells4gApi = makeCellApi<Cell4G>('4g')
export const cells5gApi = makeCellApi<Cell5G>('5g')
