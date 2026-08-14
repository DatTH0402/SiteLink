import api from './client'

export interface RncEntry {
  id: number
  vendor: string
  name: string
}

/** Fetch all RNC names, optionally filtered by vendor */
export const getRncNames = (vendor?: string): Promise<RncEntry[]> => {
  const params: Record<string, string> = {}
  if (vendor) params.vendor = vendor
  return api.get<RncEntry[]>('/api/v1/rnc/', { params }).then((r) => r.data)
}

/** Fetch all RNC names grouped by vendor: { ERICSSON: [...], HUAWEI: [...] } */
export const getRncNamesGrouped = (): Promise<Record<string, string[]>> =>
  api.get<Record<string, string[]>>('/api/v1/rnc/all').then((r) => r.data)
