/**
 * useCellSync.ts
 *
 * Key improvement: syncAfterImport captures a timestamp BEFORE the import
 * starts, then uses it to precisely query which cells were created.
 * This is 100% reliable regardless of import size or duration.
 *
 * Usage in page component:
 *
 *   const { syncAfterCreate, syncAfterImport } = useCellSync('5g', load)
 *
 *   // For DryRunModal:
 *   const importStartRef = useRef<string | null>(null)
 *
 *   importFn={async (file) => {
 *     importStartRef.current = new Date().toISOString()  // ← capture BEFORE
 *     const result = await cells5gApi.importExcel(file)
 *     syncAfterImport(result, 'cells_5g', importStartRef.current).catch(()=>{})
 *     return result
 *   }}
 */
import { useCallback } from 'react'
import toast from 'react-hot-toast'
import { syncCellsWait, syncCellsBatch, getRecentCellNames } from '@/api/sync'
import type { SyncResult } from '@/api/sync'

type CellLike = { cell_name?: string; vendor?: string }

export function useCellSync(
  tech:   '3g' | '4g' | '5g',
  reload: () => void | Promise<void>,
) {

  // ── After form create ───────────────────────────────────────────────────────
  const syncAfterCreate = useCallback(
    async (cells: CellLike[] | string[]): Promise<SyncResult | null> => {
      const isStrings = cells.length > 0 && typeof cells[0] === 'string'
      const objects: CellLike[] = isStrings
        ? (cells as string[]).map(n => ({ cell_name: n }))
        : (cells as CellLike[])

      const cellNames = objects
        .map(c => c.cell_name?.trim())
        .filter((n): n is string => Boolean(n))
      if (!cellNames.length) return null

      const vendorSet = new Set<string>()
      objects.forEach(c => {
        const v = c.vendor?.toLowerCase().trim()
        if (v && ['ericsson', 'huawei', 'nokia'].includes(v)) vendorSet.add(v)
      })

      const toastId = `sync-create-${Date.now()}`
      toast.loading(
        `⏳ Đang đồng bộ ${cellNames.length} cell ${tech.toUpperCase()}…`,
        { id: toastId, duration: 600_000 },
      )

      try {
        const resp = await syncCellsWait({
          tech,
          cell_names: cellNames,
          vendors: vendorSet.size ? [...vendorSet] : undefined,
        })
        toast.dismiss(toastId)
        _showResult(tech, resp.result, resp.duration_s)
        await reload()
        return resp.result
      } catch (err: any) {
        toast.dismiss(toastId)
        toast.error(
          `⚠️ Đồng bộ thất bại: ${err?.response?.data?.detail ?? err?.message ?? 'Lỗi'}. ` +
          `Sẽ được đồng bộ vào lần cập nhật định kỳ.`,
          { duration: 10_000 },
        )
        await reload()
        return null
      }
    },
    [tech, reload],
  )

  // ── After Excel import ──────────────────────────────────────────────────────
  /**
   * @param importResult  - response from importExcel()
   * @param tableName     - e.g. "cells_5g"
   * @param importStarted - ISO timestamp captured BEFORE importExcel() was called
   *                        If provided, uses precise timestamp query.
   *                        If omitted, falls back to 60-min window.
   */
  const syncAfterImport = useCallback(
    async (
      importResult:  any,
      tableName:     string,
      importStarted?: string,
    ): Promise<SyncResult | null> => {

      console.log('[useCellSync] syncAfterImport:', {
        tableName,
        importStarted,
        resultKeys:   importResult ? Object.keys(importResult) : null,
        created:      importResult?.created,
        updated:      importResult?.updated,
      })

      const createdCount = importResult?.created ?? importResult?.created_count ?? 0
      const updatedCount = importResult?.updated ?? importResult?.updated_count ?? 0
      const totalImported = createdCount + updatedCount

      if (totalImported === 0) {
        await reload()
        return null
      }

      // ── Strategy 1: extract cell names directly from import result ──────────
      const tryExtract = (arr: any, key = 'cell_name'): string[] =>
        Array.isArray(arr)
          ? arr.map((r: any) => typeof r === 'string' ? r : r?.[key])
               .filter((n: any): n is string => typeof n === 'string' && n.trim() !== '')
          : []

      let cellNames = [...new Set([
        ...tryExtract(importResult?.rows),
        ...tryExtract(importResult?.cells),
        ...tryExtract(importResult?.created_cells),
        ...tryExtract(importResult?.data),
        ...tryExtract(importResult?.cell_names),
      ])]

      console.log(`[useCellSync] Names from result: ${cellNames.length}, imported: ${totalImported}`)

      // ── Strategy 2: query /recent with precise timestamp ───────────────────
      // Use this if result has no names OR if count doesn't match
      const needsRecentQuery =
        cellNames.length === 0 ||
        cellNames.length < totalImported

      if (needsRecentQuery) {
        console.log('[useCellSync] Querying /recent for precise cell list...')
        try {
          const recentNames = await getRecentCellNames(tableName, {
            since:   importStarted,    // exact timestamp if available
            minutes: importStarted ? undefined : 60,  // fallback
          })
          console.log(`[useCellSync] /recent returned: ${recentNames.length} names`)

          if (recentNames.length > cellNames.length) {
            // Merge: keep all names from both sources
            cellNames = [...new Set([...cellNames, ...recentNames])]
            console.log(`[useCellSync] Merged total: ${cellNames.length} names`)
          }
        } catch (e) {
          console.warn('[useCellSync] /recent failed:', e)
        }
      }

      if (cellNames.length === 0) {
        console.warn('[useCellSync] No cell names found — reload only')
        await reload()
        return null
      }

      console.log(`[useCellSync] Syncing ${cellNames.length} cells for ${tableName}`)

      const toastId = `sync-import-${Date.now()}`
      toast.loading(
        `⏳ Đang đồng bộ ${cellNames.length} cell ${tech.toUpperCase()} từ hệ thống nguồn…` +
        (cellNames.length > 200 ? ` (có thể mất vài phút)` : ''),
        { id: toastId, duration: 600_000 },
      )

      try {
        const resp = await syncCellsBatch({
          tech,
          cell_names: cellNames,
          vendors:    undefined,
        })

        toast.dismiss(toastId)
        _showResult(tech, resp.result, resp.duration_s)
        await reload()
        return resp.result

      } catch (err: any) {
        toast.dismiss(toastId)
        toast.error(
          `⚠️ Đồng bộ thất bại: ${err?.response?.data?.detail ?? err?.message ?? 'Lỗi'}. ` +
          `Sẽ được đồng bộ vào lần cập nhật định kỳ tiếp theo.`,
          { duration: 10_000 },
        )
        await reload()
        return null
      }
    },
    [tech, reload],
  )

  return { syncAfterCreate, syncAfterImport }
}

function _showResult(tech: string, r: SyncResult, durationS?: number): void {
  const sec = durationS != null ? ` (${durationS.toFixed(1)}s)` : ''
  if (r.updated > 0) {
    const parts = [`${r.updated} cell được cập nhật`]
    if (r.skipped    > 0) parts.push(`${r.skipped} không đổi`)
    if (r.not_in_csv > 0) parts.push(`${r.not_in_csv} chưa có trong hệ thống nguồn`)
    if (r.errors     > 0) parts.push(`${r.errors} lỗi`)
    toast.success(`✅ Đồng bộ hoàn tất${sec}: ${parts.join(' · ')}`, { duration: 8_000 })
    return
  }
  if (r.not_in_csv > 0) {
    toast(
      `ℹ️ ${r.not_in_csv} cell chưa có trong hệ thống nguồn. ` +
      `Sẽ được đồng bộ tự động vào lần cập nhật định kỳ.`,
      { duration: 8_000, icon: '🔄' },
    )
    return
  }
  if (r.skipped > 0) {
    toast(`ℹ️ Đồng bộ hoàn tất${sec} — ${r.skipped} cell không đổi.`, { duration: 5_000 })
    return
  }
  toast(`ℹ️ Đồng bộ hoàn tất${sec}.`, { duration: 4_000 })
}
