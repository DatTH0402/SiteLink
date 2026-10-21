import React from 'react'
import { Tag } from 'antd'
import type { FbCategory, FbEvent, FbPriority, FbStatus } from '@/api/feedback'

export const STATUS_META: Record<FbStatus, { label: string; color: string }> = {
  new:          { label: 'Mới',             color: 'blue' },
  in_progress:  { label: 'Đang xử lý',      color: 'processing' },
  waiting_user: { label: 'Chờ phản hồi',    color: 'warning' },
  planned:      { label: 'Đã lên kế hoạch', color: 'purple' },
  resolved:     { label: 'Đã xử lý',        color: 'success' },
  closed:       { label: 'Đã đóng',         color: 'default' },
  rejected:     { label: 'Từ chối',         color: 'error' },
}

export const CATEGORY_META: Record<FbCategory, { label: string; color: string }> = {
  bug:     { label: '🐞 Báo lỗi',               color: 'red' },
  data:    { label: '🗂 Sai/thiếu dữ liệu',     color: 'volcano' },
  change:  { label: '🔧 Yêu cầu thay đổi',      color: 'geekblue' },
  feature: { label: '💡 Đề xuất tính năng',     color: 'cyan' },
  help:    { label: '❓ Cần hỗ trợ / hướng dẫn', color: 'blue' },
  account: { label: '🔑 Tài khoản / phân quyền', color: 'purple' },
  other:   { label: '📌 Khác',                  color: 'default' },
}

export const PRIORITY_META: Record<FbPriority, { label: string; color: string }> = {
  low:    { label: 'Thấp',        color: 'default' },
  normal: { label: 'Bình thường', color: 'blue' },
  high:   { label: 'Cao',         color: 'orange' },
  urgent: { label: 'Khẩn cấp',    color: 'red' },
}

const toOptions = (m: Record<string, { label: string }>) =>
  Object.entries(m).map(([value, v]) => ({ value, label: v.label }))
export const statusOptions   = toOptions(STATUS_META)
export const categoryOptions = toOptions(CATEGORY_META)
export const priorityOptions = toOptions(PRIORITY_META)

export const StatusTag = ({ v }: { v: string }) => {
  const m = (STATUS_META as Record<string, { label: string; color: string }>)[v]
  return <Tag color={m?.color}>{m?.label ?? v}</Tag>
}
export const PriorityTag = ({ v }: { v: string }) => {
  const m = (PRIORITY_META as Record<string, { label: string; color: string }>)[v]
  return <Tag color={m?.color}>{m?.label ?? v}</Tag>
}
export const CategoryTag = ({ v }: { v: string }) => {
  const m = (CATEGORY_META as Record<string, { label: string; color: string }>)[v]
  return <Tag color={m?.color}>{m?.label ?? v}</Tag>
}

export const fmtDt = (v?: string | null) => (v ? new Date(v).toLocaleString('vi-VN') : '-')
export const fmtSize = (n: number) =>
  n >= 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`

const FIELD_LABEL: Record<string, string> = {
  title: 'tiêu đề', description: 'mô tả', related_ref: 'site/cell liên quan',
}

/** one-line description of a non-comment timeline event */
export function describeEvent(e: FbEvent): string {
  const lab = (m: Record<string, { label: string }>, v?: string | null) =>
    (v && m[v]?.label) || v || '—'
  switch (e.kind) {
    case 'status':
      return `đổi trạng thái: ${lab(STATUS_META, e.old_value)} → ${lab(STATUS_META, e.new_value)}`
    case 'assign':
      return e.new_value
        ? `giao cho ${e.new_value}${e.old_value ? ` (trước đó: ${e.old_value})` : ''}`
        : `bỏ phân công${e.old_value ? ` (${e.old_value})` : ''}`
    case 'priority':
      return `đổi mức ưu tiên: ${lab(PRIORITY_META, e.old_value)} → ${lab(PRIORITY_META, e.new_value)}`
    case 'category':
      return `đổi phân loại: ${lab(CATEGORY_META, e.old_value)} → ${lab(CATEGORY_META, e.new_value)}`
    case 'due':
      return `đặt hạn xử lý: ${e.new_value ? fmtDt(e.new_value) : 'bỏ hạn'}`
    case 'edit':
      return `sửa ${FIELD_LABEL[e.body || ''] || e.body}`
    case 'resolution': return 'cập nhật kết quả xử lý'
    case 'reopen': return 'mở lại yêu cầu'
    case 'close': return 'đóng yêu cầu'
    case 'rate': return `đánh giá ${e.new_value}/5 ⭐`
    default: return e.kind
  }
}
