import api from './client'
import type { AntennaFull, CellDryRunResult, ImportResult } from '@/types'

export type { CellDryRunResult as AntennaDryRunResult, ImportResult as AntennaImportResult }

// ── CRUD ──────────────────────────────────────────────────────────────────────

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

// ── Excel import ──────────────────────────────────────────────────────────────

/**
 * Dry-run: returns a preview without saving anything.
 * Uses post<unknown> so the intermediate cast to Record<string, unknown>
 * is always valid, avoiding TS2352.
 */
export const dryRunAntennaExcel = (file: File): Promise<CellDryRunResult> => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<unknown>('/api/v1/antennas/import-excel/dry-run', form)
    .then((r) => {
      const d = r.data as Record<string, unknown>
      return {
        to_create:         Number(d.to_create      ?? 0),
        to_update:         Number(d.to_update      ?? 0),
        sites_to_create:   0,
        errors:            Number(d.errors         ?? 0),
        error_details:     (d.error_details  as string[]) ?? [],
        preview_create:    (d.preview_create as string[]) ?? [],
        preview_update:    (d.preview_update as string[]) ?? [],
        preview_new_sites: [],
        dry_run:           true as const,
      } satisfies CellDryRunResult
    })
}

/**
 * Real import: creates / updates antennas and returns counts.
 */
export const importAntennaExcel = (file: File): Promise<ImportResult> => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<ImportResult>('/api/v1/antennas/import-excel', form)
    .then((r) => r.data)
}

// ── Spec file management ──────────────────────────────────────────────────────

export const uploadAntennaSpecFile = (id: number, file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api
    .post<AntennaFull>(`/api/v1/antennas/${id}/spec-file`, form)
    .then((r) => r.data)
}

export const deleteAntennaSpecFile = (id: number) =>
  api.delete<AntennaFull>(`/api/v1/antennas/${id}/spec-file`).then((r) => r.data)

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
