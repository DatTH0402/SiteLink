import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Button, Card, Col, DatePicker, Input, Popconfirm, Row, Segmented, Select, Space,
  Statistic, Switch, Table, Typography, message,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import type { TableRowSelection } from 'antd/es/table/interface'
import {
  CommentOutlined, DeleteOutlined, DownloadOutlined, PlusOutlined,
  ReloadOutlined, SearchOutlined,
} from '@ant-design/icons'
import { useAuthStore } from '@/store/auth'
import { useDebouncedValue } from '@/hooks/useDebouncedValue'
import {
  FbStats, FbTicket, bulkDeleteTickets, bulkUpdateTickets, errText, exportTickets,
  getAssignees, getStats, listTickets, notifyFeedbackChanged, FEEDBACK_CHANGED,
} from '@/api/feedback'
import {
  CategoryTag, PriorityTag, StatusTag, categoryOptions, fmtDt, priorityOptions, statusOptions,
} from '@/components/feedback/meta'
import FeedbackFormModal from '@/components/feedback/FeedbackFormModal'

const { RangePicker } = DatePicker

const StatCard = ({ title, value, color, onClick }: {
  title: string; value: number | string; color?: string; onClick?: () => void
}) => (
  <Card size="small" hoverable={!!onClick} onClick={onClick}
        style={{ cursor: onClick ? 'pointer' : 'default' }}>
    <Statistic title={title} value={value} valueStyle={{ color, fontSize: 22 }} />
  </Card>
)

export default function FeedbackPage() {
  const navigate = useNavigate()
  const user = useAuthStore((s) => s.user)
  const isAdmin = user?.role === 'admin'

  const [rows, setRows] = useState<FbTicket[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [stats, setStats] = useState<FbStats | null>(null)
  const [assignees, setAssignees] = useState<{ id: number; name: string }[]>([])
  const [formOpen, setFormOpen] = useState(false)
  const [exporting, setExporting] = useState(false)
  const [selectedIds, setSelectedIds] = useState<number[]>([])

  const [scope, setScope] = useState<'open' | 'done' | 'all'>('open')
  const [status, setStatus] = useState<string[]>([])
  const [category, setCategory] = useState<string[]>([])
  const [priority, setPriority] = useState<string[]>([])
  const [assignee, setAssignee] = useState<string | undefined>()
  const [range, setRange] = useState<any>(null)
  const [overdue, setOverdue] = useState(false)
  const [search, setSearch] = useState('')
  const dSearch = useDebouncedValue(search, 400)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [sort, setSort] = useState<{ field: string; order: 'ascend' | 'descend' } | null>(null)
  const reqRef = useRef(0)

  const filterParams = useMemo(() => {
    const p: Record<string, unknown> = {}
    if (scope !== 'all') p.scope = scope
    if (status.length) p.status = status
    if (category.length) p.category = category
    if (priority.length) p.priority = priority
    if (isAdmin) {
      if (assignee === 'none') p.unassigned = true
      else if (assignee === 'me') p.assigned_to_me = true
      else if (assignee) p.assignee_id = Number(assignee)
    }
    if (range?.[0]) p.date_from = range[0].format('YYYY-MM-DD')
    if (range?.[1]) p.date_to = range[1].format('YYYY-MM-DD')
    if (overdue) p.overdue = true
    if (dSearch.trim()) p.search = dSearch.trim()
    return p
  }, [scope, status, category, priority, assignee, range, overdue, dSearch, isAdmin])

  useEffect(() => { setPage(1) }, [filterParams])

  const sortParams = useMemo(
    () => (sort ? { sort_by: sort.field, sort_dir: sort.order === 'ascend' ? 'asc' : 'desc' } : {}),
    [sort])

  const load = useCallback(async () => {
    const id = ++reqRef.current
    setLoading(true)
    try {
      const res = await listTickets({
        ...filterParams, ...sortParams, skip: (page - 1) * pageSize, limit: pageSize,
      })
      if (id !== reqRef.current) return
      setRows(res.items)
      setTotal(res.total)
    } catch (e: any) {
      if (id === reqRef.current) message.error(errText(e, 'Không tải được danh sách'))
    } finally {
      if (id === reqRef.current) setLoading(false)
    }
  }, [filterParams, sortParams, page, pageSize])

  const loadStats = useCallback(() => { getStats().then(setStats).catch(() => {}) }, [])
  const refreshAll = useCallback(() => { load(); loadStats() }, [load, loadStats])

  useEffect(() => { load() }, [load])
  useEffect(() => { loadStats() }, [loadStats])
  useEffect(() => { if (isAdmin) getAssignees().then(setAssignees).catch(() => {}) }, [isAdmin])
  useEffect(() => {
    window.addEventListener(FEEDBACK_CHANGED, loadStats)
    return () => window.removeEventListener(FEEDBACK_CHANGED, loadStats)
  }, [loadStats])

  const applyQuick = (q: { status?: string[]; assignee?: string; overdue?: boolean; scope?: 'open' | 'done' | 'all' }) => {
    setStatus(q.status ?? []); setAssignee(q.assignee); setOverdue(!!q.overdue)
    setScope(q.scope ?? 'all'); setCategory([]); setPriority([]); setRange(null)
    setSearch(''); setPage(1)
  }
  const clearFilters = () => applyQuick({ scope: 'open' })

  const bulk = async (changes: Record<string, unknown>) => {
    try {
      const r = await bulkUpdateTickets(selectedIds, changes)
      if (r.updated) message.success(`Đã cập nhật ${r.updated} yêu cầu`)
      if (r.errors.length) message.warning(r.errors.slice(0, 3).join('; '))
      setSelectedIds([]); refreshAll(); notifyFeedbackChanged()
    } catch (e: any) { message.error(errText(e)) }
  }
  const bulkDelete = async () => {
    try {
      const r = await bulkDeleteTickets(selectedIds)
      message.success(`Đã xóa ${r.deleted} yêu cầu`)
      setSelectedIds([]); refreshAll(); notifyFeedbackChanged()
    } catch (e: any) { message.error(errText(e)) }
  }
  const doExport = async () => {
    setExporting(true)
    try { await exportTickets({ ...filterParams, ...sortParams }) }
    catch (e: any) { message.error(errText(e, 'Xuất thất bại')) }
    finally { setExporting(false) }
  }

  const so = (f: string) => (sort?.field === f ? sort.order : null)
  const colCreator: ColumnsType<FbTicket>[number] = {
    title: 'Người gửi', dataIndex: 'created_by_name', key: 'created_by_name', width: 150,
    sorter: true, sortOrder: so('created_by_name'), ellipsis: true,
  }
  const colAssignee: ColumnsType<FbTicket>[number] = {
    title: 'Người xử lý', dataIndex: 'assignee_name', key: 'assignee_name', width: 150,
    sorter: true, sortOrder: so('assignee_name'),
    render: (v: string | null) => v || <span style={{ color: '#bbb' }}>Chưa phân công</span>,
  }
  const columns: ColumnsType<FbTicket> = [
    { title: 'Mã', dataIndex: 'id', key: 'id', width: 95, sorter: true, sortOrder: so('id'),
      render: (_: unknown, r: FbTicket) => <Typography.Link>{r.code}</Typography.Link> },
    { title: 'Tiêu đề', dataIndex: 'title', key: 'title', width: 340, sorter: true, sortOrder: so('title'),
      render: (_: unknown, r: FbTicket) => (
        <div>
          <strong>{r.title}</strong>
          {r.comment_count > 0 && (
            <span style={{ color: '#999', marginLeft: 8 }}><CommentOutlined /> {r.comment_count}</span>
          )}
          {r.related_ref && <div style={{ fontSize: 12, color: '#888' }}>{r.related_ref}</div>}
        </div>
      ) },
    { title: 'Loại', dataIndex: 'category', key: 'category', width: 190, sorter: true, sortOrder: so('category'),
      render: (v: string) => <CategoryTag v={v} /> },
    { title: 'Ưu tiên', dataIndex: 'priority', key: 'priority', width: 110, sorter: true, sortOrder: so('priority'),
      render: (v: string) => <PriorityTag v={v} /> },
    { title: 'Trạng thái', dataIndex: 'status', key: 'status', width: 130, sorter: true, sortOrder: so('status'),
      render: (v: string) => <StatusTag v={v} /> },
    ...(isAdmin ? [colCreator] : []),
    colAssignee,
    { title: 'Tạo lúc', dataIndex: 'created_at', key: 'created_at', width: 150, sorter: true, sortOrder: so('created_at'),
      render: (v: string) => fmtDt(v) },
    { title: 'Cập nhật', dataIndex: 'last_activity_at', key: 'last_activity_at', width: 150, sorter: true,
      sortOrder: so('last_activity_at'), render: (v: string) => fmtDt(v) },
    { title: 'Hạn xử lý', dataIndex: 'due_date', key: 'due_date', width: 150, sorter: true, sortOrder: so('due_date'),
      render: (v: string | null, r: FbTicket) =>
        v ? <span style={{ color: r.overdue ? '#cf1322' : undefined, fontWeight: r.overdue ? 700 : 400 }}>
              {fmtDt(v)}{r.overdue ? ' ⚠' : ''}</span> : '-' },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  const rowSelection: TableRowSelection<FbTicket> = {
    selectedRowKeys: selectedIds, preserveSelectedRowKeys: true,
    onChange: (keys) => setSelectedIds(keys as number[]),
  }

  const bs = stats?.by_status ?? {}
  const adminCards = [
    { title: 'Mới', value: bs.new ?? 0, color: '#1677ff', on: () => applyQuick({ status: ['new'] }) },
    { title: 'Đang xử lý', value: bs.in_progress ?? 0, color: '#13a8a8', on: () => applyQuick({ status: ['in_progress'] }) },
    { title: 'Chờ phản hồi', value: bs.waiting_user ?? 0, color: '#d48806', on: () => applyQuick({ status: ['waiting_user'] }) },
    { title: 'Chưa phân công', value: stats?.unassigned ?? 0, color: '#d46b08', on: () => applyQuick({ assignee: 'none', scope: 'open' }) },
    { title: 'Quá hạn', value: stats?.overdue ?? 0, color: '#cf1322', on: () => applyQuick({ overdue: true }) },
    { title: 'TB phản hồi đầu (giờ)', value: stats?.avg_first_response_h ?? '-', color: undefined, on: undefined },
    { title: 'TB xử lý xong (giờ)', value: stats?.avg_resolution_h ?? '-', color: undefined, on: undefined },
  ]
  const userCards = [
    { title: 'Tổng yêu cầu', value: stats?.total ?? 0, color: undefined, on: () => applyQuick({ scope: 'all' }) },
    { title: 'Đang mở', value: stats?.open ?? 0, color: '#1677ff', on: () => applyQuick({ scope: 'open' }) },
    { title: 'Chờ bạn phản hồi', value: bs.waiting_user ?? 0, color: '#d48806', on: () => applyQuick({ status: ['waiting_user'] }) },
    { title: 'Đã xử lý', value: (bs.resolved ?? 0) + (bs.closed ?? 0), color: '#389e0d', on: () => applyQuick({ status: ['resolved', 'closed'] }) },
  ]
  const cards = isAdmin ? adminCards : userCards

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>
          {isAdmin ? 'Hỗ trợ & Góp ý – Tất cả yêu cầu' : 'Hỗ trợ & Góp ý – Yêu cầu của tôi'}
        </Typography.Title>
        <Space>
          {isAdmin && (
            <Button icon={<DownloadOutlined />} loading={exporting} onClick={doExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>Xuất Excel</Button>
          )}
          <Button icon={<ReloadOutlined />} onClick={refreshAll}>Làm mới</Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setFormOpen(true)}>
            Tạo yêu cầu mới
          </Button>
        </Space>
      </Row>

      <Row gutter={[8, 8]} style={{ marginBottom: 12 }}>
        {cards.map((c) => (
          <Col key={c.title} flex="1 1 140px">
            <StatCard title={c.title} value={c.value} color={c.color} onClick={c.on} />
          </Col>
        ))}
      </Row>

      <Row gutter={[8, 8]} style={{ marginBottom: 8 }} align="middle">
        <Col>
          <Segmented value={scope} onChange={(v) => setScope(v as any)}
            options={[{ label: 'Đang mở', value: 'open' }, { label: 'Đã hoàn tất', value: 'done' }, { label: 'Tất cả', value: 'all' }]} />
        </Col>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} allowClear value={search}
                 placeholder="Tìm mã, tiêu đề, nội dung, site/cell..."
                 onChange={(e) => setSearch(e.target.value)} />
        </Col>
        <Col flex="190px">
          <Select mode="multiple" allowClear maxTagCount={1} placeholder="Trạng thái" style={{ width: '100%' }}
                  value={status} onChange={setStatus} options={statusOptions} />
        </Col>
        <Col flex="190px">
          <Select mode="multiple" allowClear maxTagCount={1} placeholder="Loại" style={{ width: '100%' }}
                  value={category} onChange={setCategory} options={categoryOptions} />
        </Col>
        <Col flex="170px">
          <Select mode="multiple" allowClear maxTagCount={1} placeholder="Ưu tiên" style={{ width: '100%' }}
                  value={priority} onChange={setPriority} options={priorityOptions} />
        </Col>
        {isAdmin && (
          <Col flex="200px">
            <Select allowClear placeholder="Người xử lý" style={{ width: '100%' }} value={assignee}
                    onChange={(v) => setAssignee(v)}
                    options={[
                      { value: 'me', label: '👤 Của tôi' },
                      { value: 'none', label: '⚪ Chưa phân công' },
                      ...assignees.map((a) => ({ value: String(a.id), label: a.name })),
                    ]} />
          </Col>
        )}
        <Col><RangePicker value={range} onChange={(v) => setRange(v)} format="DD/MM/YYYY"
                          placeholder={['Từ ngày', 'Đến ngày']} /></Col>
        <Col><Space size={4}><Switch size="small" checked={overdue} onChange={setOverdue} />Quá hạn</Space></Col>
        <Col><Button onClick={clearFilters}>Xóa lọc</Button></Col>
      </Row>

      {isAdmin && selectedIds.length > 0 && (
        <Space wrap style={{ background: '#e6f7ff', border: '1px solid #91d5ff', borderRadius: 6,
                             padding: '8px 16px', marginBottom: 12 }}>
          <Typography.Text strong>Đã chọn {selectedIds.length} yêu cầu</Typography.Text>
          <Select placeholder="Đổi trạng thái" style={{ width: 160 }} value={undefined}
                  options={statusOptions} onChange={(v) => bulk({ status: v })} />
          <Select placeholder="Giao cho" style={{ width: 170 }} value={undefined}
                  options={assignees.map((a) => ({ value: a.id, label: a.name }))}
                  onChange={(v) => bulk({ assignee_id: v })} />
          <Select placeholder="Đổi ưu tiên" style={{ width: 140 }} value={undefined}
                  options={priorityOptions} onChange={(v) => bulk({ priority: v })} />
          <Popconfirm title={`Xóa ${selectedIds.length} yêu cầu?`} description="Không thể hoàn tác."
                      onConfirm={bulkDelete}>
            <Button danger icon={<DeleteOutlined />}>Xóa</Button>
          </Popconfirm>
          <Button onClick={() => setSelectedIds([])}>Bỏ chọn</Button>
        </Space>
      )}

      <Table<FbTicket>
        rowKey="id" size="small" bordered loading={loading}
        columns={columns} dataSource={rows}
        rowSelection={isAdmin ? rowSelection : undefined}
        scroll={{ x: scrollX }}
        onChange={(_p, _f, s: any, extra) => {
          if (extra.action !== 'sort') return
          const one = Array.isArray(s) ? s[0] : s
          setSort(one?.order ? { field: String(one.columnKey ?? one.field), order: one.order } : null)
          setPage(1)
        }}
        pagination={{
          current: page, pageSize, total, showSizeChanger: true,
          pageSizeOptions: [10, 20, 50, 100],
          showTotal: (t) => `${t.toLocaleString('vi-VN')} yêu cầu`,
          onChange: (p, s) => { setPage(p); setPageSize(s) },
        }}
        onRow={(r) => ({
          style: { cursor: 'pointer' },
          onClick: (e) => {
            if ((e.target as HTMLElement).closest('.ant-checkbox-wrapper, .ant-table-selection-column')) return
            navigate(`/feedback/${r.id}`)
          },
        })}
      />

      <FeedbackFormModal
        open={formOpen} onClose={() => setFormOpen(false)}
        onCreated={(t) => { message.success(`Đã gửi yêu cầu ${t.code}`); refreshAll(); navigate(`/feedback/${t.id}`) }}
      />
    </div>
  )
}
