import dayjs from 'dayjs'
import api from './client'
import { pagedGet } from './listing'

export type FbStatus = 'new' | 'in_progress' | 'waiting_user' | 'planned' | 'resolved' | 'closed' | 'rejected'
export type FbCategory = 'bug' | 'data' | 'change' | 'feature' | 'help' | 'account' | 'other'
export type FbPriority = 'low' | 'normal' | 'high' | 'urgent'

export interface FbTicket {
  id: number
  code: string
  title: string
  category: FbCategory
  priority: FbPriority
  status: FbStatus
  related_ref?: string | null
  created_by?: number | null
  created_by_name?: string | null
  created_by_email?: string | null
  assignee_id?: number | null
  assignee_name?: string | null
  due_date?: string | null
  overdue: boolean
  resolution?: string | null
  rating?: number | null
  rating_comment?: string | null
  reopen_count: number
  comment_count: number
  created_at: string
  updated_at?: string | null
  last_activity_at?: string | null
  first_response_at?: string | null
  resolved_at?: string | null
  closed_at?: string | null
  is_owner: boolean
}

export interface FbEvent {
  id: number
  kind: string
  body?: string | null
  old_value?: string | null
  new_value?: string | null
  is_internal: boolean
  user_id?: number | null
  user_name?: string | null
  user_role?: string | null
  created_at: string
}

export interface FbAttachment {
  id: number
  filename: string
  content_type?: string | null
  size: number
  event_id?: number | null
  uploaded_by?: number | null
  uploaded_by_name?: string | null
  created_at: string
  is_image: boolean
}

export interface FbDetail extends FbTicket {
  description: string
  page_url?: string | null
  user_agent?: string | null
  events: FbEvent[]
  attachments: FbAttachment[]
}

export interface FbStats {
  total: number
  open: number
  by_status: Record<string, number>
  by_category: Record<string, number>
  by_priority_open: Record<string, number>
  unassigned: number
  overdue: number
  avg_first_response_h: number | null
  avg_resolution_h: number | null
}

const B = '/api/v1/feedback'
export const FEEDBACK_CHANGED = 'feedback:changed'
export const notifyFeedbackChanged = () => window.dispatchEvent(new Event(FEEDBACK_CHANGED))

export const errText = (e: any, fallback = 'Có lỗi xảy ra'): string => {
  const d = e?.response?.data?.detail
  if (typeof d === 'string') return d
  if (Array.isArray(d)) return d.map((x: any) => x?.msg).filter(Boolean).join('; ') || fallback
  return e?.message || fallback
}

export const listTickets = (params?: Record<string, unknown>) => pagedGet<FbTicket>(`${B}/`, params)
export const getStats = () => api.get<FbStats>(`${B}/stats`).then((r) => r.data)
export const getBadge = () => api.get<{ count: number }>(`${B}/badge`).then((r) => r.data.count)
export const getAssignees = () =>
  api.get<{ id: number; name: string }[]>(`${B}/assignees`).then((r) => r.data)
export const getTicket = (id: number) => api.get<FbDetail>(`${B}/${id}`).then((r) => r.data)
export const createTicket = (data: Record<string, unknown>) =>
  api.post<FbDetail>(`${B}/`, data).then((r) => r.data)
export const updateTicket = (id: number, data: Record<string, unknown>) =>
  api.patch<FbDetail>(`${B}/${id}`, data).then((r) => r.data)
export const addComment = (id: number, data: { body: string; is_internal?: boolean }) =>
  api.post<FbEvent>(`${B}/${id}/comments`, data).then((r) => r.data)
export const uploadAttachments = (id: number, files: File[], eventId?: number) => {
  const form = new FormData()
  files.forEach((f) => form.append('files', f))
  if (eventId) form.append('event_id', String(eventId))
  return api.post<FbAttachment[]>(`${B}/${id}/attachments`, form).then((r) => r.data)
}
export const deleteAttachment = (attId: number) => api.delete(`${B}/attachments/${attId}`)
export const reopenTicket = (id: number, reason?: string) =>
  api.post<FbDetail>(`${B}/${id}/reopen`, { reason }).then((r) => r.data)
export const closeTicket = (id: number, reason?: string) =>
  api.post<FbDetail>(`${B}/${id}/close`, { reason }).then((r) => r.data)
export const rateTicket = (id: number, rating: number, comment?: string) =>
  api.post<FbDetail>(`${B}/${id}/rate`, { rating, comment }).then((r) => r.data)
export const deleteTicket = (id: number) => api.delete(`${B}/${id}`)
export const bulkUpdateTickets = (ids: number[], changes: Record<string, unknown>) =>
  api.post<{ updated: number; errors: string[] }>(`${B}/bulk-update`, { ids, changes }).then((r) => r.data)
export const bulkDeleteTickets = (ids: number[]) =>
  api.post<{ deleted: number }>(`${B}/bulk-delete`, { ids }).then((r) => r.data)

export async function exportTickets(params: Record<string, unknown>) {
  const r = await api.get(`${B}/export`, { params, responseType: 'blob' })
  const url = URL.createObjectURL(r.data as Blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `Feedback_${dayjs().format('YYYYMMDD_HHmm')}.xlsx`
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

/** download a file, or (images, download=false) open it in a new tab */
export async function openAttachment(att: FbAttachment, download = true) {
  const r = await api.get(`${B}/attachments/${att.id}/download`, { responseType: 'blob' })
  const url = URL.createObjectURL(r.data as Blob)
  if (!download && att.is_image) {
    window.open(url, '_blank')
    setTimeout(() => URL.revokeObjectURL(url), 60_000)
    return
  }
  const a = document.createElement('a')
  a.href = url
  a.download = att.filename
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
