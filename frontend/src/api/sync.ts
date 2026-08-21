/**
 * sync.ts — Cell sync API
 */
import api from './client'

export interface SyncRequest {
  tech:       '3g' | '4g' | '5g'
  cell_names: string[]
  vendors?:   string[]
}

export interface SyncResult {
  updated:       number
  skipped:       number
  not_in_db:     number
  not_in_csv:    number
  errors:        number
  error_details: string[]
}

export interface SyncWaitResponse {
  table_name: string
  cell_count: number
  result:     SyncResult
  duration_s: number
}

/** Sync small batches (form create). */
export const syncCellsWait = (req: SyncRequest): Promise<SyncWaitResponse> =>
  api.post<SyncWaitResponse>('/api/v1/sync/cells/wait', req, {
    timeout: 600_000,
  }).then(r => r.data)

/** Sync large batches (import). CSVs downloaded once. */
export const syncCellsBatch = (req: SyncRequest): Promise<SyncWaitResponse> =>
  api.post<SyncWaitResponse>('/api/v1/sync/cells/batch', req, {
    timeout: 600_000,
  }).then(r => r.data)

/**
 * Get cell_names created/updated after a specific timestamp.
 * Pass `since` as ISO string captured BEFORE the import started.
 * Falls back to `minutes` window if `since` not provided.
 * Returns up to 50000 names.
 */
export const getRecentCellNames = (
  table:   string,
  options: { since?: string; minutes?: number } = {},
): Promise<string[]> => {
  const params = new URLSearchParams({ table })
  if (options.since)   params.set('since', options.since)
  if (options.minutes) params.set('minutes', String(options.minutes))
  return api.get<{ cell_names: string[]; count: number }>(
    `/api/v1/sync/recent?${params}`
  ).then(r => r.data.cell_names ?? [])
}
