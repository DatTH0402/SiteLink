import api from './client'
import type { AntennaFull, CellDryRunResult } from '@/types'

export const getAntennas = (params?: Record<string, unknown>) =>
  api.get<AntennaFull[]>('/api/v1/antennas/', { params }).then((r) => r.data)

export const getAntenna = (id: number) =>
  api.get<AntennaFull>(`/api/v1/antennas/${id}`).then((r) => r.data)

export const createAntenna = (data: Partial<AntennaFull>) =>
  api.post<AntennaFull>('/api/v1/antennas/', data).then((r) => r.data)

export const updateAntenna = (id: number, data: Partial<AntennaFull>) =>
  api.put<AntennaFull>(`/api/v1/antennas/${id}`, data).then((r) => r.data)

export const deleteAntenna = (id: number) =>
  api.delete(`/api/v1/antennas/${id}`)

export const dryRunAntennaExcel = (file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post('/api/v1/antennas/import-excel?dry_run=true', form)
    .then((r) => r.data)
}

export const importAntennaExcel = (file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post('/api/v1/antennas/import-excel', form)
    .then((r) => r.data)
}
