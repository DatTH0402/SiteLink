/**
 * export.ts – Downloads exported Excel / KMZ files from the backend.
 *
 * Sites / Cells exports use POST so that a large selection (thousands of ids)
 * and the column filters fit in the request. Scope rule (enforced server-side):
 *   - `ids` present  -> exactly the selected rows
 *   - otherwise      -> top-bar filters + column filters (+ sort)
 */

function getToken(): string {
  return localStorage.getItem('sl_token') || ''
}

export interface ExportResult {
  /** rows written to the file */
  rows?: number
  /** (KMZ only) sites that had valid coordinates */
  valid?: number
}

/** Extra scope on top of the top-bar filters. Build it with `buildExportScope`. */
export interface ExportScope {
  ids?:      number[]
  filters?:  string            // column filters JSON (same string as the list `filters` param)
  sort_by?:  string
  sort_dir?: 'asc' | 'desc'
}

/** Minimal shape of `useServerQuery()` that we need. */
interface ServerQueryLike {
  filtersJson?: string
  sort: { field: string; order: 'ascend' | 'descend' } | null
}

/**
 * Selected rows win (exact export). With no selection, export everything the
 * table currently shows as filtered (top-bar + column filters), same sort order.
 */
export function buildExportScope(sq: ServerQueryLike, selectedIds: number[] = []): ExportScope {
  const scope: ExportScope = {}
  if (sq.sort) {
    scope.sort_by  = sq.sort.field
    scope.sort_dir = sq.sort.order === 'ascend' ? 'asc' : 'desc'
  }
  if (selectedIds.length > 0) scope.ids = selectedIds
  else if (sq.filtersJson)    scope.filters = sq.filtersJson
  return scope
}

function headerNum(res: Response, name: string): number | undefined {
  const raw = res.headers.get(name)
  if (raw === null || raw === '') return undefined
  const n = Number(raw)
  return Number.isFinite(n) ? n : undefined
}

async function fetchAndSave(url: string, init: RequestInit, filename: string): Promise<ExportResult> {
  const res = await fetch(url, init)
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Export failed (${res.status}): ${text}`)
  }
  const blob = await res.blob()
  const link = document.createElement('a')
  link.href     = URL.createObjectURL(blob)
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(link.href)
  return {
    rows:  headerNum(res, 'X-Row-Count') ?? headerNum(res, 'X-Site-Count'),
    valid: headerNum(res, 'X-Valid-Coords'),
  }
}

function getBlob(url: string, filename: string) {
  return fetchAndSave(url, { headers: { Authorization: `Bearer ${getToken()}` } }, filename)
}

type FilterValue = string | string[] | undefined | null

function cleanParams(params: Record<string, FilterValue>): Record<string, string | string[]> {
  const out: Record<string, string | string[]> = {}
  Object.entries(params).forEach(([k, v]) => {
    if (v === undefined || v === null || v === '') return
    if (Array.isArray(v)) {
      const arr = v.filter((x) => x !== '' && x !== undefined && x !== null)
      if (arr.length) out[k] = arr
    } else {
      out[k] = v
    }
  })
  return out
}

function postExport(
  path: string, filename: string,
  params: Record<string, FilterValue>, scope?: ExportScope,
) {
  const hasIds = Boolean(scope?.ids && scope.ids.length > 0)
  const body = {
    // when rows are selected the server ignores every other filter
    params:   hasIds ? {} : cleanParams(params),
    ids:      hasIds ? scope!.ids : undefined,
    filters:  hasIds ? undefined : scope?.filters,
    sort_by:  scope?.sort_by,
    sort_dir: scope?.sort_dir ?? 'asc',
  }
  return fetchAndSave(
    `/api/v1/export/${path}`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${getToken()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
    filename,
  )
}

// ── Sites ────────────────────────────────────────────────────────────────────
export interface SiteExportFilters {
  search?:       string
  site_name_cu?: string
  mien?:         string[]
  tinh?:         string[]
  phuong_xa?:    string[]
}

export const exportSites = (filters: SiteExportFilters = {}, scope?: ExportScope) =>
  postExport('sites', 'Sites_Export.xlsx', filters as Record<string, FilterValue>, scope)

export const exportSitesKmz = (filters: SiteExportFilters = {}, scope?: ExportScope) =>
  postExport('sites-kmz', 'Sites_Export.kmz', filters as Record<string, FilterValue>, scope)

// ── Cells ────────────────────────────────────────────────────────────────────
export interface CellExportFilters {
  search?:        string
  cell_name_old?: string
  mien?:          string[]
  tinh?:          string[]
  phuong_xa?:     string[]
  vendor?:        string[]
  mimo?:          string[]
  vung_phu_song?: string[]
}

export const exportCells3G = (filters: CellExportFilters = {}, scope?: ExportScope) =>
  postExport('cells-3g', 'Cells_3G_Export.xlsx', filters as Record<string, FilterValue>, scope)

export const exportCells4G = (filters: CellExportFilters = {}, scope?: ExportScope) =>
  postExport('cells-4g', 'Cells_4G_Export.xlsx', filters as Record<string, FilterValue>, scope)

export const exportCells5G = (filters: CellExportFilters = {}, scope?: ExportScope) =>
  postExport('cells-5g', 'Cells_5G_Export.xlsx', filters as Record<string, FilterValue>, scope)

// ── Antennas (unchanged, GET) ────────────────────────────────────────────────
function buildQS(params: Record<string, FilterValue>): string {
  const qs = new URLSearchParams()
  Object.entries(params).forEach(([k, v]) => {
    if (v === undefined || v === null) return
    if (Array.isArray(v)) {
      v.forEach((item) => { if (item) qs.append(k, item) })
    } else if (v !== '') {
      qs.append(k, v)
    }
  })
  const s = qs.toString()
  return s ? `?${s}` : ''
}

export function exportAntennas(filters: { search?: string; band?: string }) {
  return getBlob(`/api/v1/export/antennas${buildQS(filters)}`, 'Antennas_Export.xlsx')
}

// ── KMZ (Google Earth) with visualisation options ────────────────────────────
export type KmzLayer = 'sites' | 'cells-3g' | 'cells-4g' | 'cells-5g'
export type KmzFilters = Record<string, string | string[] | undefined | null>

export interface KmzChoice { value: string; label: string }

export interface KmzMeta {
  layer: string
  title: string
  file_label: string
  folders: KmzChoice[]
  default_folder: string
  color_columns: KmzChoice[]
  default_color: string
  color_label: string
  has_icon: boolean
  icon_columns: KmzChoice[]
  default_icon: string | null
  icon_label: string
  color_modes: KmzChoice[]
  default_color_mode: string
  has_opacity: boolean
  opacities: KmzChoice[]
  default_opacity: string
  note: string
}

export async function getKmzMeta(layer: KmzLayer): Promise<KmzMeta> {
  const res = await fetch(`/api/v1/export/kmz/meta/${layer}`, {
    headers: { Authorization: `Bearer ${getToken()}` },
  })
  if (!res.ok) throw new Error(`Không tải được cấu hình KMZ (${res.status})`)
  return res.json()
}

/**
 * Scope rule is identical to the Excel export: selected ids win, otherwise
 * top-bar filters + column filters (+ sort). `options` = styling choices.
 */
export async function exportKmz(
  layer: KmzLayer,
  filters: KmzFilters,
  scope: ExportScope | undefined,
  options: Record<string, unknown>,
): Promise<ExportResult & { filename: string }> {
  const hasIds = Boolean(scope?.ids && scope.ids.length > 0)
  const body = {
    params:   hasIds ? {} : cleanParams(filters),
    ids:      hasIds ? scope!.ids : undefined,
    filters:  hasIds ? undefined : scope?.filters,
    sort_by:  scope?.sort_by,
    sort_dir: scope?.sort_dir ?? 'asc',
    options,
  }
  const res = await fetch(`/api/v1/export/kmz/${layer}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${getToken()}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Export failed (${res.status}): ${text}`)
  }
  const cd = res.headers.get('Content-Disposition') || ''
  const m = /filename="?([^";]+)"?/i.exec(cd)
  const filename = m ? m[1] : `KMZ-${layer}.kmz`
  const blob = await res.blob()
  const link = document.createElement('a')
  link.href     = URL.createObjectURL(blob)
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(link.href)
  return {
    rows:  headerNum(res, 'X-Row-Count'),
    valid: headerNum(res, 'X-Valid-Coords'),
    filename,
  }
}
