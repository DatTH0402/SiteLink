export interface User {
  id: number
  email: string
  username: string
  full_name?: string
  role: 'admin' | 'user'
  is_active: boolean
  auth_provider: 'local' | 'sso'
}

export interface Site {
  id: number
  mien: string
  tinh: string
  phuong_xa?: string
  site_name_cu?: string
  site_name: string
  site_vip?: string
  lat: number
  long: number
  tram_2g: boolean
  tram_3g: boolean
  tram_4g: boolean
  tram_5g: boolean
  repeater: boolean
  booster: boolean
  node_truyen_dan_only: boolean
  tram_phu_song_tsca: boolean
  phan_loai_tram?: string
  moran_3g?: string
  moran_4g?: string
  moran_5g?: string
  ma_ptm: string
  do_cao_dinh_cot_anten?: number
  do_cao_cot_anten?: number
  dia_chi?: string
  ghi_chu?: string
}

export interface CellBase {
  id: number
  site_id: number
  mien?: string
  tinh?: string
  phuong_xa?: string
  site_name: string
  cell_name: string
  cell_vip?: string
  moran?: string
  lat?: number
  long?: number
  vung_phu_song?: string
  vendor?: string
  do_cao_anten?: number
  azimuth?: number
  m_tilt?: number
  e_tilt?: number
  total_tilt?: number
  loai_anten?: string
  baseband?: string
  rf?: string
  cell_id?: string
  mimo?: string
}

export interface Cell3G extends CellBase {
  chung_anten?: string
  arfcn?: string
  psc?: string
}

export interface Cell4G extends CellBase {
  chung_anten?: string
  earfcn?: string
  pci?: string
  root_sequence_id?: string
}

export interface Cell5G extends CellBase {
  nr_arfcn?: string
  pci?: string
  root_sequence_id?: string
}

export interface ReportRow {
  mien?: string
  tinh?: string
  site_count: number
  site_2g: number
  site_3g: number
  site_4g: number
  site_5g: number
  cell_3g: number
  cell_4g: number
  cell_5g: number
}

export interface AuditLog {
  id: number
  username: string
  full_name: string
  email: string
  action: string
  table_name: string
  record_id: number
  old_value?: string
  new_value?: string
  timestamp: string
}

export interface TinhItem {
  ten_tinh: string
  mien: string
}

export interface PhuongXaItem {
  id: number
  mien: string
  ten_tinh: string
  ten_phuong_xa: string
  ma_tinh: string
  ma_phuong_xa: string
  ky_tu_1_6: string
}

export interface AntennaItem {
  id: number
  name: string
  band?: string
  no_of_ports?: number
  no_of_beam?: number
  horizontal_bw?: string
  vertical_bw?: string
  gain?: string
  etilt?: string
  h?: string
  w?: string
  d?: string
  weight?: string
  connector_type?: string
  ghi_chu?: string
}

export interface ProvinceChartItem {
  tinh: string
  site_count: number
}

export interface CellProvinceChartItem {
  tinh: string
  cell_count: number
}

export interface SiteDryRunResult {
  to_create: number
  to_update: number
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  dry_run: true
}

export interface CellDryRunResult {
  to_create: number
  to_update: number
  sites_to_create: number
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  preview_new_sites: string[]
  dry_run: true
}

export interface ImportResult {
  created: number
  updated: number
  sites_auto_created?: number
  errors: string[]
}

export interface AntennaFull {
  id: number
  name: string
  no_of_ports?: number
  band?: string
  no_of_beam?: number
  horizontal_bw?: string
  vertical_bw?: string
  gain?: string
  etilt?: string
  h?: string
  w?: string
  d?: string
  weight?: string
  connector_type?: string
  ghi_chu?: string
}
