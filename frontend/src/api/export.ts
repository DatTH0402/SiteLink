/**
 * export.ts – Downloads exported Excel files from the backend.
 * Multi-value filter arrays are serialized as repeated query params:
 *   tinh=HN&tinh=HCM  (not tinh[]=HN&tinh[]=HCM)
 */

function getToken(): string {
  return localStorage.getItem('sl_token') || ''
}

async function downloadBlob(url: string, filename: string): Promise<void> {
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${getToken()}` },
  })
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
}

type FilterValue = string | string[] | undefined | null

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

export function exportSites(filters: {
  search?: string
  mien?:   string[]
  tinh?:   string[]
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/sites${qs}`, 'Sites_Export.xlsx')
}

export function exportCells3G(filters: {
  search?:        string
  mien?:          string[]
  tinh?:          string[]
  vendor?:        string[]
  mimo?:          string[]
  vung_phu_song?: string[]
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/cells-3g${qs}`, 'Cells_3G_Export.xlsx')
}

export function exportCells4G(filters: {
  search?:        string
  mien?:          string[]
  tinh?:          string[]
  vendor?:        string[]
  mimo?:          string[]
  vung_phu_song?: string[]
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/cells-4g${qs}`, 'Cells_4G_Export.xlsx')
}

export function exportCells5G(filters: {
  search?:        string
  mien?:          string[]
  tinh?:          string[]
  vendor?:        string[]
  mimo?:          string[]
  vung_phu_song?: string[]
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/cells-5g${qs}`, 'Cells_5G_Export.xlsx')
}

export function exportAntennas(filters: {
  search?: string
  band?:   string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/antennas${qs}`, 'Antennas_Export.xlsx')
}
