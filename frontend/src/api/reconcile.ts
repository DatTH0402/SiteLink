/**
 * reconcile.ts - API client of the dump <-> web cell reconciliation dashboard.
 */
import api from './client'
import { pagedGet, idsGet, distinctGet } from './listing'
import type { ExportScope } from './export'

export type ReconTech = '3g' | '4g' | '5g'
export type ReconDirection = 'missing_in_web' | 'missing_in_dump'

export interface ReconRun {
  id: number
  tech: ReconTech
  batch_id?: string | null
  run_date?: string | null
  started_at?: string | null
  finished_at?: string | null
  status: string
  error?: string | null
  prev_run_id?: number | null
  dump_total: number
  dump_active: number
  dump_inactive: number
  web_total: number
  matched: number
  missing_in_web: number
  missing_in_dump: number
  missing_in_dump_uncovered: number
  dump_inactive_not_in_web: number
  new_missing_in_web: number
  new_missing_in_dump: number
  resolved_missing_in_web: number
  resolved_missing_in_dump: number
  vendor_status?: {
    files?: Record<string, { ok: boolean; rows: number }>
    notes?: string[]
    duplicate_names?: number
  } | null
  status_stats?: { status: string; active: boolean; count: number }[] | null
}

export interface ReconTechSummary {
  run: ReconRun | null
  last_run: ReconRun | null
  vendors: { direction: ReconDirection; vendor: string; covered: boolean; count: number }[]
  provinces: { direction: ReconDirection; tinh: string; count: number }[]
}

export interface ReconHistoryPoint {
  run_date: string
  missing_in_web: number
  missing_in_dump: number
  dump_active: number
  web_total: number
}

export interface ReconSummary {
  techs: Record<ReconTech, ReconTechSummary>
  history: Record<ReconTech, ReconHistoryPoint[]>
  generated_at: string
}

export interface ReconItem {
  id: number
  tech: ReconTech
  direction: ReconDirection
  cell_name: string
  subcell_id?: string | null
  web_id?: number | null
  site_name?: string | null
  vendor?: string | null
  mien?: string | null
  tinh?: string | null
  phuong_xa?: string | null
  cell_status?: string | null
  bbu_name?: string | null
  rf?: string | null
  oss?: string | null
  dump_date?: string | null
  cell_id?: string | null
  node_id?: string | null
  freq?: string | null
  pci?: string | null
  tac?: string | null
  bandwidth?: string | null
  mimo?: string | null
  web_updated_at?: string | null
  first_seen?: string | null
  dump_covered?: string | null
  age_days?: number | null
}

const BASE = '/api/v1/reconcile'

export const reconcileApi = {
  summary: () => api.get<ReconSummary>(`${BASE}/summary`).then((r) => r.data),
  list: (params?: Record<string, unknown>) => pagedGet<ReconItem>(`${BASE}/items`, params),
  ids: (params?: Record<string, unknown>) => idsGet(`${BASE}/items`, params),
  distinct: (column: string, params?: Record<string, unknown>) =>
    distinctGet(`${BASE}/items`, column, params),
}

// ── downloads ────────────────────────────────────────────────────────────────
const token = () => localStorage.getItem('sl_token') || ''

async function saveResponse(res: Response, fallback: string): Promise<{ filename: string; rows?: number }> {
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Export failed (${res.status}): ${text}`)
  }
  const cd = res.headers.get('Content-Disposition') || ''
  const m = /filename="?([^";]+)"?/i.exec(cd)
  const filename = m ? m[1] : fallback
  const blob = await res.blob()
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(link.href)
  const raw = res.headers.get('X-Row-Count')
  const n = raw === null || raw === '' ? NaN : Number(raw)
  return { filename, rows: Number.isFinite(n) ? n : undefined }
}

function cleanParams(params: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  Object.entries(params).forEach(([k, v]) => {
    if (v === undefined || v === null || v === '' || v === false) return
    if (Array.isArray(v) && v.length === 0) return
    out[k] = v
  })
  return out
}

/** Selected ids win; otherwise top-bar params + column filters (+ sort). */
export async function exportReconcile(
  tech: ReconTech,
  direction: ReconDirection,
  params: Record<string, unknown>,
  scope?: ExportScope,
) {
  const hasIds = Boolean(scope?.ids && scope.ids.length > 0)
  const body = {
    tech,
    direction,
    params: hasIds ? {} : cleanParams(params),
    ids: hasIds ? scope!.ids : undefined,
    filters: hasIds ? undefined : scope?.filters,
    sort_by: scope?.sort_by,
    sort_dir: scope?.sort_dir ?? 'asc',
  }
  const res = await fetch(`${BASE}/export`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  return saveResponse(res, `Doi_soat_${tech}_${direction}.xlsx`)
}

export async function exportReconcileAll() {
  const res = await fetch(`${BASE}/export-all`, { headers: { Authorization: `Bearer ${token()}` } })
  return saveResponse(res, 'Doi_soat_cell_tong_hop.xlsx')
}
