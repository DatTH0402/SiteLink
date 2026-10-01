import api from './client'

export interface DistinctItem {
  value: string | number | boolean | null
  count: number
}
export interface DistinctResult {
  values: DistinctItem[]
  total_distinct: number
}
export interface Paged<T> {
  items: T[]
  total: number
}

/** GET a list endpoint and read the total from the X-Total-Count header. */
export async function pagedGet<T>(
  url: string, params?: Record<string, unknown>,
): Promise<Paged<T>> {
  const r = await api.get<T[]>(url, { params })
  const h = Number((r.headers as any)['x-total-count'])
  return { items: r.data, total: Number.isFinite(h) ? h : r.data.length }
}

export const distinctGet = (
  base: string, column: string, params?: Record<string, unknown>,
) =>
  api.get<DistinctResult>(`${base}/distinct/${encodeURIComponent(column)}`, { params })
     .then((r) => r.data)

export const idsGet = (base: string, params?: Record<string, unknown>) =>
  api.get<{ ids: number[]; total: number }>(`${base}/ids`, { params })
     .then((r) => r.data.ids)
