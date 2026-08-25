/**
 * templates.ts
 * ------------
 * API calls for Excel template download.
 * Always uses cache-busting (?t=timestamp) so browsers never serve
 * a stale cached copy of the template file.
 */
import api from './client'

export type TemplateName = 'site' | 'cell-3g' | 'cell-4g' | 'cell-5g' | 'antenna'

export interface TemplateInfo {
  name:          string
  filename:      string
  exists:        boolean
  size_bytes:    number
  last_modified: number
  etag:          string
}

/**
 * Download a template file.
 * Uses fetch() directly so we can intercept the blob response
 * and force the browser to save it (bypasses browser cache).
 */
export async function downloadTemplate(name: TemplateName): Promise<void> {
  const token = localStorage.getItem('sl_token') || ''

  // Cache-busting timestamp query param – ensures browser never uses
  // a cached copy even if Cache-Control headers are ignored by the browser.
  const url = `/api/v1/templates/${name}?t=${Date.now()}`

  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${token}`,
      // Explicitly tell browser not to use cache
      'Cache-Control': 'no-cache',
      'Pragma':        'no-cache',
    },
    // 'no-store' mode tells the browser fetch API to bypass its cache
    cache: 'no-store',
  })

  if (!res.ok) {
    const detail = await res.text().catch(() => res.statusText)
    throw new Error(`Download failed (${res.status}): ${detail}`)
  }

  const blob        = await res.blob()
  const disposition = res.headers.get('Content-Disposition') || ''
  const match       = disposition.match(/filename[^;=\n]*=["']?([^"'\n;]*)["']?/)
  const filename    = match?.[1] || `Template_${name}.xlsx`

  const link    = document.createElement('a')
  link.href     = URL.createObjectURL(blob)
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(link.href)
}

/**
 * Get template metadata without downloading.
 * Use this to check if a template was recently updated.
 */
export async function getTemplateInfo(name: TemplateName): Promise<TemplateInfo> {
  const res = await api.get<TemplateInfo>(
    `/api/v1/templates/info/${name}`,
    {
      params: { t: Date.now() },    // cache-busting
      headers: { 'Cache-Control': 'no-cache' },
    }
  )
  return res.data
}

/**
 * Get info for all templates.
 */
export async function getAllTemplatesInfo(): Promise<TemplateInfo[]> {
  const res = await api.get<TemplateInfo[]>(
    '/api/v1/templates/',
    {
      params: { t: Date.now() },
      headers: { 'Cache-Control': 'no-cache' },
    }
  )
  return res.data
}
