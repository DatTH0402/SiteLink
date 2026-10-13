/**
 * sync.ts - Cell sync API
 *
 * syncCellsWait / syncCellsBatch keep their old signatures, but they now start a
 * background job (POST /sync/cells) and poll it. Nothing holds an HTTP request
 * open for minutes, so the reverse proxy's 120 s timeout can no longer cut a sync.
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
  meta_only?:    number
}

export interface SyncWaitResponse {
  table_name: string
  cell_count: number
  result:     SyncResult
  duration_s: number
}

interface JobStart {
  job_id:     string
  status:     string
  cell_count: number
  message:    string
}

interface JobStatus {
  job_id:       string
  status:       string
  started_at?:  string | null
  finished_at?: string | null
  result?:      Record<string, unknown> | null
  error?:       string | null
}

const POLL_MS     = 2000
const MAX_WAIT_MS = 30 * 60 * 1000

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))
const num   = (v: unknown): number => (typeof v === 'number' ? v : 0)

async function runSyncJob(req: SyncRequest): Promise<SyncWaitResponse> {
  const t0 = Date.now()
  const start = await api
    .post<JobStart>('/api/v1/sync/cells', req, { timeout: 60_000 })
    .then((r) => r.data)

  let failures = 0
  while (Date.now() - t0 < MAX_WAIT_MS) {
    await sleep(POLL_MS)
    let st: JobStatus
    try {
      st = await api
        .get<JobStatus>(`/api/v1/sync/status/${start.job_id}`, { timeout: 30_000 })
        .then((r) => r.data)
      failures = 0
    } catch (e) {
      failures += 1
      if (failures >= 5) throw e      // tolerate a few transient network errors
      continue
    }

    if (st.status === 'done') {
      const r = st.result ?? {}
      return {
        table_name: `cells_${req.tech}`,
        cell_count: req.cell_names.length,
        result: {
          updated:       num(r.updated),
          skipped:       num(r.skipped),
          not_in_db:     num(r.not_in_db),
          not_in_csv:    num(r.not_in_csv),
          errors:        num(r.errors),
          meta_only:     num(r.meta_only),
          error_details: Array.isArray(r.error_details) ? (r.error_details as string[]) : [],
        },
        duration_s: (Date.now() - t0) / 1000,
      }
    }
    if (st.status === 'error') throw new Error(st.error || 'Sync failed')
  }
  throw new Error('Sync is still running after 30 minutes - it will finish in the background.')
}

/** Sync small batches (form create). */
export const syncCellsWait = (req: SyncRequest): Promise<SyncWaitResponse> => runSyncJob(req)

/** Sync large batches (import). CSVs are downloaded once (and cached server-side). */
export const syncCellsBatch = (req: SyncRequest): Promise<SyncWaitResponse> => runSyncJob(req)

/**
 * Get cell_names created/updated after a specific timestamp.
 * (Fallback only: the import endpoints now return the touched cell names directly.)
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
