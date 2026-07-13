/**
 * revision.ts
 * -----------
 * API client for revision history endpoints.
 */
import api from './client'

export interface SiteRevision {
  id: number
  site_id: number
  site_name: string
  site_name_old_ref?: string
  revision_no: number
  changed_by_name: string
  change_source: 'form' | 'excel'
  change_note?: string
  changed_fields: Record<string, [unknown, unknown]>
  created_at: string
  // site fields snapshot
  mien?: string
  tinh?: string
  phuong_xa?: string
  site_name_cu?: string
  site_vip?: string
  lat?: number
  long?: number
  tram_2g?: boolean
  tram_3g?: boolean
  tram_4g?: boolean
  tram_5g?: boolean
  repeater?: boolean
  booster?: boolean
  node_truyen_dan_only?: boolean
  tram_phu_song_tsca?: boolean
  phan_loai_tram?: string
  moran_3g?: string
  moran_4g?: string
  moran_5g?: string
  ma_ptm?: string
  do_cao_dinh_cot_anten?: number
  do_cao_cot_anten?: number
  dia_chi?: string
  ghi_chu?: string
}

export interface CellRevisionBase {
  id: number
  cell_id_ref: number
  site_id: number
  site_name: string
  site_name_old?: string
  cell_name: string
  cell_name_old?: string
  revision_no: number
  changed_by_name: string
  change_source: 'form' | 'excel'
  change_note?: string
  changed_fields: Record<string, [unknown, unknown]>
  created_at: string
  mien?: string
  tinh?: string
  vendor?: string
  azimuth?: number
  mimo?: string
  [key: string]: unknown
}

// Sites
export const getSiteRevisions = (params: Record<string, unknown>) =>
  api.get<SiteRevision[]>('/api/v1/revisions/sites', { params }).then(r => r.data)

export const getSiteRevisionById = (siteId: number) =>
  api.get<SiteRevision[]>(`/api/v1/revisions/sites/${siteId}`).then(r => r.data)

// Cells
export const getCell3GRevisions = (params: Record<string, unknown>) =>
  api.get<CellRevisionBase[]>('/api/v1/revisions/cells-3g', { params }).then(r => r.data)

export const getCell4GRevisions = (params: Record<string, unknown>) =>
  api.get<CellRevisionBase[]>('/api/v1/revisions/cells-4g', { params }).then(r => r.data)

export const getCell5GRevisions = (params: Record<string, unknown>) =>
  api.get<CellRevisionBase[]>('/api/v1/revisions/cells-5g', { params }).then(r => r.data)
