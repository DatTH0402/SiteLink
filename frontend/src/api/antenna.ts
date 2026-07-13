import api from './client'
import type { AntennaFull } from '@/types'

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
  return api.post('/api/v1/antennas/import-excel', form).then((r) => r.data)
}

/**
 * Upload a PDF spec file for an antenna.
 * Returns the updated AntennaFull object.
 */
export const uploadAntennaSpecFile = (id: number, file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<AntennaFull>(`/api/v1/antennas/${id}/spec-file`, form)
    .then((r) => r.data)
}

/**
 * Remove the spec file from an antenna.
 */
export const deleteAntennaSpecFile = (id: number) =>
  api.delete<AntennaFull>(`/api/v1/antennas/${id}/spec-file`).then((r) => r.data)

/**
 * Download the spec file (opens as Blob → triggers browser download).
 */
export async function downloadAntennaSpecFile(
  id: number,
  fileName: string,
): Promise<void> {
  const token = localStorage.getItem('sl_token') || ''
  const res   = await fetch(`/api/v1/antennas/${id}/spec-file/download`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) throw new Error(`Download failed (${res.status})`)
  const blob = await res.blob()
  const link = document.createElement('a')
  link.href     = URL.createObjectURL(blob)
  link.download = fileName
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(link.href)
}
