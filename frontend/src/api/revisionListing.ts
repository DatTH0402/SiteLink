/**
 * revisionListing.ts
 * ------------------
 * Server-side listing (paging / column filters / select-all) and CSV export
 * for the revision endpoints. Same pattern as api/sites.ts.
 */
import api from './client'
import { pagedGet, idsGet, distinctGet } from './listing'

export type RevisionLayer = 'sites' | 'cells-3g' | 'cells-4g' | 'cells-5g'

const base = (layer: RevisionLayer) => `/api/v1/revisions/${layer}`

export const getRevisionsPaged = <T>(layer: RevisionLayer, params?: Record<string, unknown>) =>
  pagedGet<T>(base(layer), params)

export const getRevisionIds = (layer: RevisionLayer, params?: Record<string, unknown>) =>
  idsGet(base(layer), params)

export const getRevisionDistinct = (
  layer: RevisionLayer, column: string, params?: Record<string, unknown>,
) => distinctGet(base(layer), column, params)

// ── CSV export ───────────────────────────────────────────────────────────────
export interface RevisionCsvColumn { field: string; title: string }

export interface RevisionCsvRequest {
  ids?:      number[]
  filters?:  string
  params?:   Record<string, unknown>
  sort_by?:  string
  sort_dir?: 'asc' | 'desc'
  columns:   RevisionCsvColumn[]
}

async function errorText(err: any): Promise<string> {
  const data = err?.response?.data
  if (data instanceof Blob) {
    try {
      const txt = await data.text()
      try {
        const j = JSON.parse(txt)
        return typeof j?.detail === 'string' ? j.detail : txt
      } catch { return txt }
    } catch { /* ignore */ }
  }
  return err?.response?.data?.detail || err?.message || 'Xuất CSV thất bại'
}

export async function exportRevisionCsv(
  layer: RevisionLayer, body: RevisionCsvRequest,
): Promise<{ rows?: number; filename: string }> {
  let res
  try {
    res = await api.post(`${base(layer)}/export-csv`, body, { responseType: 'blob' })
  } catch (err: any) {
    throw new Error(await errorText(err))
  }
  const h = res.headers as any
  const cd: string = h?.['content-disposition'] || ''
  const m = /filename="?([^";]+)"?/i.exec(cd)
  const filename = m ? m[1] : `Revision_${layer}.csv`
  const rawRows = Number(h?.['x-row-count'])

  const blob = new Blob([res.data], { type: 'text/csv;charset=utf-8' })
  const link = document.createElement('a')
  link.href     = URL.createObjectURL(blob)
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(link.href)
  return { rows: Number.isFinite(rawRows) ? rawRows : undefined, filename }
}
