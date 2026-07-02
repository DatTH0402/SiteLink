import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col, Alert,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { getSites, deleteSite, dryRunSitesExcel, importSitesExcel } from '@/api/sites'
import type { Site } from '@/types'
import DryRunModal from '@/components/shared/DryRunModal'

const boolCell = (v: boolean) =>
  v ? <Tag color="green">x</Tag> : <Tag color="default">-</Tag>

export default function SitesPage() {
  const navigate    = useNavigate()
  const [sites,     setSites]     = useState<Site[]>([])
  const [loading,   setLoading]   = useState(false)
  const [search,    setSearch]    = useState('')
  const [mien,      setMien]      = useState<string | undefined>()
  const [tinh,      setTinh]      = useState<string | undefined>()
  const [loadError, setLoadError] = useState<string | null>(null)
  const [dryRunOpen, setDryRunOpen] = useState(false)

  const tinhOptions = [
    ...new Set(sites.map((s) => s.tinh).filter((t): t is string => Boolean(t))),
  ].sort()

  const load = () => {
    setLoading(true)
    setLoadError(null)
    getSites({ search: search || undefined, mien: mien || undefined,
               tinh: tinh || undefined, limit: 500 })
      .then(setSites)
      .catch((err) => {
        const detail = err?.response?.data?.detail || err?.message || 'Unknown error'
        setLoadError(`Cannot load sites: ${detail}`)
      })
      .finally(() => setLoading(false))
  }

  useEffect(() => { load() }, [search, mien, tinh])

  const handleDelete = async (id: number) => {
    try {
      await deleteSite(id)
      message.success('Da xoa site')
      load()
    } catch (err: any) {
      const detail = err?.response?.data?.detail || 'Xoa that bai'
      message.error(detail)
    }
  }

  const columns: ColumnsType<Site> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Site) => (
        <Space>
          <Button size="small" icon={<EditOutlined />}
                  onClick={() => navigate(`/sites/${r.id}/edit`)} />
          <Popconfirm
            title="Xoa site nay?"
            description="Neu site con cell, thao tac se bi tu choi."
            onConfirm={() => handleDelete(r.id)}
          >
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Mien', dataIndex: 'mien', fixed: 'left', width: 70,
      sorter: (a, b) => (a.mien||'').localeCompare(b.mien||'') },
    { title: 'Tinh', dataIndex: 'tinh', fixed: 'left', width: 160,
      sorter: (a, b) => (a.tinh||'').localeCompare(b.tinh||'') },
    { title: 'Phuong xa',      dataIndex: 'phuong_xa',    width: 160 },
    { title: 'Site name (cu)', dataIndex: 'site_name_cu', width: 200, ellipsis: { showTitle: true } },
    { title: 'Site name', dataIndex: 'site_name', fixed: 'left', width: 220,
      sorter: (a, b) => (a.site_name||'').localeCompare(b.site_name||''),
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Site VIP', dataIndex: 'site_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'Lat',  dataIndex: 'lat',  width: 110 },
    { title: 'Long', dataIndex: 'long', width: 110 },
    { title: 'Tram 2G', dataIndex: 'tram_2g', width: 80, render: boolCell },
    { title: 'Tram 3G', dataIndex: 'tram_3g', width: 80, render: boolCell },
    { title: 'Tram 4G', dataIndex: 'tram_4g', width: 80, render: boolCell },
    { title: 'Tram 5G', dataIndex: 'tram_5g', width: 80, render: boolCell },
    { title: 'Repeater', dataIndex: 'repeater', width: 90, render: boolCell },
    { title: 'Booster',  dataIndex: 'booster',  width: 85, render: boolCell },
    { title: 'Node truyen dan only',
      dataIndex: 'node_truyen_dan_only', width: 160, render: boolCell },
    { title: 'Tram phu song TSCA',
      dataIndex: 'tram_phu_song_tsca',   width: 160, render: boolCell },
    { title: 'Phan loai tram', dataIndex: 'phan_loai_tram', width: 180 },
    { title: 'MORAN 3G', dataIndex: 'moran_3g', width: 120 },
    { title: 'MORAN 4G', dataIndex: 'moran_4g', width: 120 },
    { title: 'MORAN 5G', dataIndex: 'moran_5g', width: 120 },
    { title: 'Ma PTM',   dataIndex: 'ma_ptm',   width: 120 },
    { title: 'Do cao dinh cot anten (m)',
      dataIndex: 'do_cao_dinh_cot_anten', width: 190 },
    { title: 'Do cao cot anten mat san (m)',
      dataIndex: 'do_cao_cot_anten', width: 210 },
    { title: 'Dia chi', dataIndex: 'dia_chi', width: 200, ellipsis: { showTitle: true } },
    { title: 'Ghi chu', dataIndex: 'ghi_chu', width: 200, ellipsis: { showTitle: true } },
  ]

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quan ly Site</Typography.Title>
        <Space>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />}
                  onClick={() => navigate('/sites/new')}>
            Them moi
          </Button>
        </Space>
      </Row>

      {loadError && (
        <Alert message={loadError} type="error" showIcon closable
               style={{ marginBottom: 12 }} onClose={() => setLoadError(null)} />
      )}

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map((m) =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="200px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(input, opt) =>
                    String(opt?.children ?? '').toLowerCase().includes(input.toLowerCase())}>
            {tinhOptions.map((t) =>
              <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien(undefined); setTinh(undefined) }}>
            Xoa loc
          </Button>
        </Col>
        <Col>
          <Button onClick={load} loading={loading}>Lam moi</Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={sites} rowKey="id"
             loading={loading} size="small"
             scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} sites`,
                           showSizeChanger: true }} />

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Site tu Excel"
        templateKey="site"
        dryRunFn={dryRunSitesExcel}
        importFn={importSitesExcel}
        onSuccess={load}
      />
    </div>
  )
}
