/**
 * export.ts
 * ---------
 * Downloads exported Excel files from the backend.
 * Uses fetch + Blob so Authorization header can be sent.
 * Active filters are passed as query params so the export
 * matches exactly what the user sees on screen.
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

function buildQS(params: Record<string, string | undefined>): string {
  const qs = new URLSearchParams()
  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== '') qs.append(k, v)
  })
  const s = qs.toString()
  return s ? `?${s}` : ''
}

// ── Sites ─────────────────────────────────────────────────────────────────────
export function exportSites(filters: {
  search?: string
  mien?:   string
  tinh?:   string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/sites${qs}`, 'Sites_Export.xlsx')
}

// ── Cells 3G ──────────────────────────────────────────────────────────────────
export function exportCells3G(filters: {
  search?:        string
  mien?:          string
  tinh?:          string
  vendor?:        string
  mimo?:          string
  vung_phu_song?: string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/cells-3g${qs}`, 'Cells_3G_Export.xlsx')
}

// ── Cells 4G ──────────────────────────────────────────────────────────────────
export function exportCells4G(filters: {
  search?:        string
  mien?:          string
  tinh?:          string
  vendor?:        string
  mimo?:          string
  vung_phu_song?: string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/cells-4g${qs}`, 'Cells_4G_Export.xlsx')
}

// ── Cells 5G ──────────────────────────────────────────────────────────────────
export function exportCells5G(filters: {
  search?:        string
  mien?:          string
  tinh?:          string
  vendor?:        string
  mimo?:          string
  vung_phu_song?: string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/cells-5g${qs}`, 'Cells_5G_Export.xlsx')
}

// ── Antennas ──────────────────────────────────────────────────────────────────
export function exportAntennas(filters: {
  search?: string
  band?:   string
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/antennas${qs}`, 'Antennas_Export.xlsx')
}
