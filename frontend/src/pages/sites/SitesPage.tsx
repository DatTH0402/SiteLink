import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col, Alert, Tooltip,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import type { TableRowSelection } from 'antd/es/table/interface'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import {
  getSites, deleteSite, dryRunSitesExcel, importSitesExcel,
  bulkDeleteSites, bulkUpdateSites,
} from '@/api/sites'
import { exportSites } from '@/api/export'
import { getDropdown, getTinhList } from '@/api/report'
import type { Site, TinhItem } from '@/types'
import DryRunModal from '@/components/shared/DryRunModal'
import SiteBulkEditModal from '@/components/shared/SiteBulkEditModal'

const boolCell = (v: boolean) =>
  v ? <Tag color="green">x</Tag> : <Tag color="default">-</Tag>

export default function SitesPage() {
  const navigate = useNavigate()
  const [sites,        setSites]        = useState<Site[]>([])
  const [loading,      setLoading]      = useState(false)
  const [exporting,    setExporting]    = useState(false)
  const [search,       setSearch]       = useState('')
  const [mien,         setMien]         = useState<string[]>([])
  const [tinh,         setTinh]         = useState<string[]>([])
  const [loadError,    setLoadError]    = useState<string | null>(null)
  const [dryRunOpen,   setDryRunOpen]   = useState(false)
  const [selectedIds,  setSelectedIds]  = useState<number[]>([])
  const [bulkEditOpen, setBulkEditOpen] = useState(false)
  const [phanLoaiOpts, setPhanLoaiOpts] = useState<string[]>([])
  const [tinhList,     setTinhList]     = useState<TinhItem[]>([])

  const tinhOptions = tinhList.length > 0
    ? tinhList.map(t => t.ten_tinh)
    : [...new Set(sites.map(s => s.tinh).filter((t): t is string => Boolean(t)))].sort()

  const load = () => {
    setLoading(true)
    setLoadError(null)
    const params: Record<string, unknown> = { limit: 500 }
    if (search)      params.search = search
    if (mien.length) params.mien   = mien
    if (tinh.length) params.tinh   = tinh
    getSites(params)
      .then(setSites)
      .catch(err => {
        const detail = err?.response?.data?.detail || err?.message || 'Unknown error'
        setLoadError(`Cannot load sites: ${detail}`)
      })
      .finally(() => setLoading(false))
  }

  useEffect(() => { load() }, [search, mien, tinh])

  useEffect(() => {
    getDropdown('phan_loai_tram').then((rows: any[]) =>
      setPhanLoaiOpts(rows.map(r => r.value)))
    getTinhList().then(setTinhList)
  }, [])

  const handleDelete = async (id: number) => {
    try {
      await deleteSite(id)
      message.success('Đã xóa site')
      setSelectedIds(prev => prev.filter(x => x !== id))
      load()
    } catch (err: any) {
      message.error(err?.response?.data?.detail || 'Xóa thất bại')
    }
  }

  const handleBulkDelete = async () => {
    const result = await bulkDeleteSites(selectedIds)
    if (result.deleted > 0) message.success(`Đã xóa ${result.deleted} site`)
    if (result.errors.length > 0)
      message.warning(`${result.errors.length} lỗi: ${result.errors.slice(0, 3).join('; ')}`)
    setSelectedIds([])
    load()
  }

  const handleBulkEdit = async (changes: Record<string, unknown>) => {
    try {
      const result = await bulkUpdateSites(selectedIds, changes)
      if (result.updated && result.updated > 0)
        message.success(`Đã cập nhật ${result.updated} site`)
      if (result.errors && result.errors.length > 0) {
        message.error({
          content: (
            <div>
              <div><strong>{result.errors.length} lỗi khi cập nhật:</strong></div>
              {result.errors.slice(0, 5).map((e: string, i: number) => (
                <div key={i} style={{ fontSize: 12, fontFamily: 'monospace' }}>{e}</div>
              ))}
              {result.errors.length > 5 && (
                <div style={{ color: '#999' }}>...và {result.errors.length - 5} lỗi khác</div>
              )}
            </div>
          ),
          duration: 8,
        })
      }
    } catch (err: any) {
      const detail = err?.response?.data?.detail || err?.message || 'Lỗi không xác định'
      message.error(`Bulk update thất bại: ${detail}`)
    }
    setSelectedIds([])
    load()
  }

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportSites({
        search: search || undefined,
        mien:   mien.length ? mien : undefined,
        tinh:   tinh.length ? tinh : undefined,
      })
      message.success(`Xuất Excel thành công (${sites.length} sites)`)
    } catch (e: any) {
      message.error(e?.message || 'Xuất thất bại')
    } finally {
      setExporting(false)
    }
  }

  const rowSelection: TableRowSelection<Site> = {
    selectedRowKeys: selectedIds,
    onChange: keys => setSelectedIds(keys as number[]),
    selections: [Table.SELECTION_ALL, Table.SELECTION_INVERT, Table.SELECTION_NONE],
  }

  const columns: ColumnsType<Site> = [
    {
      title: 'Hành động', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Site) => (
        <Space>
          <Button size="small" icon={<EditOutlined />}
                  onClick={() => navigate(`/sites/${r.id}/edit`)} />
          <Popconfirm
            title="Xóa site này?"
            description="Nếu site có cell, thao tác sẽ bị từ chối."
            onConfirm={() => handleDelete(r.id)}
          >
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Miền',  dataIndex: 'mien',  fixed: 'left', width: 70,
      sorter: (a, b) => (a.mien||'').localeCompare(b.mien||'') },
    { title: 'Tỉnh',  dataIndex: 'tinh',  fixed: 'left', width: 160,
      sorter: (a, b) => (a.tinh||'').localeCompare(b.tinh||'') },
    { title: 'Phường xã',      dataIndex: 'phuong_xa',    width: 160 },
    { title: 'Site name (cũ)', dataIndex: 'site_name_cu', width: 200,
      ellipsis: { showTitle: true } },
    { title: 'Site name', dataIndex: 'site_name', fixed: 'left', width: 220,
      sorter: (a, b) => (a.site_name||'').localeCompare(b.site_name||''),
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Site VIP', dataIndex: 'site_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'Lat',  dataIndex: 'lat',  width: 110 },
    { title: 'Long', dataIndex: 'long', width: 110 },
    { title: 'Trạm 2G', dataIndex: 'tram_2g', width: 80,  render: boolCell },
    { title: 'Trạm 3G', dataIndex: 'tram_3g', width: 80,  render: boolCell },
    { title: 'Trạm 4G', dataIndex: 'tram_4g', width: 80,  render: boolCell },
    { title: 'Trạm 5G', dataIndex: 'tram_5g', width: 80,  render: boolCell },
    { title: 'Repeater', dataIndex: 'repeater', width: 90, render: boolCell },
    { title: 'Booster',  dataIndex: 'booster',  width: 85, render: boolCell },
    { title: 'Node truyền dẫn only', dataIndex: 'node_truyen_dan_only',
      width: 160, render: boolCell },
    { title: 'Trạm phủ sóng TSCA', dataIndex: 'tram_phu_song_tsca',
      width: 160, render: boolCell },
    { title: 'Phân loại trạm', dataIndex: 'phan_loai_tram', width: 180 },
    { title: 'MORAN 3G', dataIndex: 'moran_3g', width: 120 },
    { title: 'MORAN 4G', dataIndex: 'moran_4g', width: 120 },
    { title: 'MORAN 5G', dataIndex: 'moran_5g', width: 120 },
    { title: 'Mã PTM',   dataIndex: 'ma_ptm',   width: 120 },
    { title: 'Độ cao đỉnh cột anten (m)', dataIndex: 'do_cao_dinh_cot_anten', width: 190 },
    { title: 'Độ cao cột anten mặt đất (m)', dataIndex: 'do_cao_cot_anten',   width: 210 },
    { title: 'Địa chỉ', dataIndex: 'dia_chi', width: 200, ellipsis: { showTitle: true } },
    { title: 'Ghi chú', dataIndex: 'ghi_chu', width: 200, ellipsis: { showTitle: true } },
  ]

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quản lý site</Typography.Title>
        <Space>
          <Tooltip title="Xuất dữ liệu hiện tại ra Excel">
            <Button icon={<DownloadOutlined />} loading={exporting} onClick={handleExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>
              Xuất Excel ({sites.length})
            </Button>
          </Tooltip>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={() => navigate('/sites/new')}>
            Thêm mới
          </Button>
        </Space>
      </Row>

      {loadError && (
        <Alert message={loadError} type="error" showIcon closable
               style={{ marginBottom: 12 }} onClose={() => setLoadError(null)} />
      )}

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tìm site name..."
                 value={search} onChange={e => setSearch(e.target.value)} allowClear />
        </Col>
        <Col flex="180px">
          <Select mode="multiple" placeholder="Miền" allowClear maxTagCount={2}
                  style={{ width: '100%' }} value={mien} onChange={setMien}>
            {['MB','MT','MN'].map(m => (
              <Select.Option key={m} value={m}>{m}</Select.Option>
            ))}
          </Select>
        </Col>
        <Col flex="260px">
          <Select mode="multiple" placeholder="Tỉnh" allowClear showSearch maxTagCount={2}
                  style={{ width: '100%' }} value={tinh} onChange={setTinh}
                  filterOption={(input, opt) =>
                    String(opt?.children ?? '').toLowerCase().includes(input.toLowerCase())}>
            {tinhOptions.map(t => (
              <Select.Option key={t} value={t}>{t}</Select.Option>
            ))}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien([]); setTinh([]) }}>Xóa lọc</Button>
        </Col>
        <Col>
          <Button onClick={load} loading={loading}>Làm mới</Button>
        </Col>
      </Row>

      {selectedIds.length > 0 && (
        <Row style={{ marginBottom: 12 }}>
          <Col>
            <Space style={{
              background: '#e6f7ff', border: '1px solid #91d5ff',
              borderRadius: 6, padding: '8px 16px',
            }}>
              <Typography.Text strong>Đã chọn {selectedIds.length} site</Typography.Text>
              <Button type="primary" icon={<EditOutlined />}
                      onClick={() => setBulkEditOpen(true)}>
                Sửa hàng loạt
              </Button>
              <Popconfirm
                title={`Xóa ${selectedIds.length} site đã chọn?`}
                description="Site có cell sẽ bị bỏ qua."
                onConfirm={handleBulkDelete}
              >
                <Button danger icon={<DeleteOutlined />}>Xóa hàng loạt</Button>
              </Popconfirm>
              <Button onClick={() => setSelectedIds([])}>Bỏ chọn</Button>
            </Space>
          </Col>
        </Row>
      )}

      <Table
        rowSelection={rowSelection}
        columns={columns}
        dataSource={sites}
        rowKey="id"
        loading={loading}
        size="small"
        scroll={{ x: scrollX, y: 600 }}
        bordered
        pagination={{ pageSize: 50, showTotal: t => `${t} sites`, showSizeChanger: true }}
      />

      {/* New SiteBulkEditModal – uses real Switch/booleans, tracks touched fields */}
      <SiteBulkEditModal
        open={bulkEditOpen}
        onClose={() => setBulkEditOpen(false)}
        count={selectedIds.length}
        phanLoaiOpts={phanLoaiOpts}
        onConfirm={handleBulkEdit}
      />

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Site từ Excel"
        templateKey="site"
        dryRunFn={dryRunSitesExcel}
        importFn={importSitesExcel}
        onSuccess={load}
      />
    </div>
  )
}
