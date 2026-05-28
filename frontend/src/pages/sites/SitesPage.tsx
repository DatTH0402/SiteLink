import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, Upload, message, Row, Col, Modal,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { getSites, deleteSite, importSitesExcel } from '@/api/sites'
import type { Site } from '@/types'

const boolCell = (v: boolean) => v ? <Tag color="green">x</Tag> : <Tag color="default">-</Tag>

export default function SitesPage() {
  const navigate  = useNavigate()
  const [sites,   setSites]   = useState<Site[]>([])
  const [loading, setLoading] = useState(false)
  const [search,  setSearch]  = useState('')
  const [mien,    setMien]    = useState<string | undefined>()

  const load = async () => {
    setLoading(true)
    try { setSites(await getSites({ search, mien, limit: 500 })) }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [search, mien])

  const handleDelete = async (id: number) => {
    await deleteSite(id)
    message.success('Da xoa site')
    load()
  }

  const handleImport = async (file: File) => {
    try {
      const res = await importSitesExcel(file)
      if (res.created > 0) message.success(`Da nhap ${res.created} site`)
      if (res.errors?.length) {
        // Show first 5 errors in modal so user can see them
        Modal.error({
          title: `${res.errors.length} dong bi loi`,
          width: 700,
          content: (
            <div style={{ maxHeight: 400, overflowY: 'auto' }}>
              {res.errors.slice(0, 20).map((e: string, i: number) => (
                <div key={i} style={{ padding: '4px 0', borderBottom: '1px solid #f0f0f0',
                                      fontSize: 12, fontFamily: 'monospace' }}>
                  {e}
                </div>
              ))}
              {res.errors.length > 20 && (
                <div style={{ color: '#999', marginTop: 8 }}>
                  ... va {res.errors.length - 20} loi khac
                </div>
              )}
            </div>
          ),
        })
      }
      if (res.created > 0) load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Import that bai')
    }
    return false
  }

  const columns: ColumnsType<Site> = [
    // ── fixed action column on the left ──────────────────────────────
    {
      title: 'Hanh dong',
      key: 'action',
      fixed: 'left',
      width: 80,
      render: (_: unknown, r: Site) => (
        <Space>
          <Button size="small" icon={<EditOutlined />}
                  onClick={() => navigate(`/sites/${r.id}/edit`)} />
          <Popconfirm title="Xoa site nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    // ── columns in exact spec order ───────────────────────────────────
    { title: 'Mien',          dataIndex: 'mien',                 fixed: 'left', width: 70  },
    { title: 'Tinh',          dataIndex: 'tinh',                 fixed: 'left', width: 130 },
    { title: 'Phuong xa',     dataIndex: 'phuong_xa',            width: 130 },
    { title: 'Site name (cu)',dataIndex: 'site_name_cu',          width: 130 },
    {
      title: 'Site name', dataIndex: 'site_name', width: 130, fixed: 'left',
      render: (v: string) => <strong>{v}</strong>,
    },
    {
      title: 'Site VIP', dataIndex: 'site_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-',
    },
    { title: 'Lat',  dataIndex: 'lat',  width: 110 },
    { title: 'Long', dataIndex: 'long', width: 110 },
    {
      title: 'Tram 2G', dataIndex: 'tram_2g', width: 80,
      render: boolCell,
    },
    {
      title: 'Tram 3G', dataIndex: 'tram_3g', width: 80,
      render: boolCell,
    },
    {
      title: 'Tram 4G', dataIndex: 'tram_4g', width: 80,
      render: boolCell,
    },
    {
      title: 'Tram 5G', dataIndex: 'tram_5g', width: 80,
      render: boolCell,
    },
    {
      title: 'Repeater', dataIndex: 'repeater', width: 90,
      render: boolCell,
    },
    {
      title: 'Booster', dataIndex: 'booster', width: 85,
      render: boolCell,
    },
    {
      title: 'Node truyen dan only', dataIndex: 'node_truyen_dan_only', width: 160,
      render: boolCell,
    },
    { title: 'IBC/Macro outdoor/...', dataIndex: 'phan_loai_tram',      width: 180 },
    { title: 'Tram phu song TSCA',    dataIndex: 'tram_phu_song_tsca',   width: 160 },
    { title: 'MORAN 3G',              dataIndex: 'moran_3g',             width: 120 },
    { title: 'MORAN 4G',              dataIndex: 'moran_4g',             width: 120 },
    { title: 'MORAN 5G',              dataIndex: 'moran_5g',             width: 120 },
    { title: 'Ma PTM',                dataIndex: 'ma_ptm',               width: 120 },
    { title: 'Do cao dinh cot anten (m)', dataIndex: 'do_cao_dinh_cot_anten', width: 190 },
    { title: 'Do cao cot anten mat san (m)', dataIndex: 'do_cao_cot_anten',   width: 210 },
    { title: 'Dia chi',               dataIndex: 'dia_chi',              width: 200 },
    { title: 'Ghi chu',               dataIndex: 'ghi_chu',              width: 200 },
  ]

  // total scroll width = sum of all column widths
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quan ly Site</Typography.Title>
        <Space>
          <Upload beforeUpload={handleImport} accept=".xlsx,.xls" showUploadList={false}>
            <Button icon={<UploadOutlined />}>Import Excel</Button>
          </Upload>
          <Button type="primary" icon={<PlusOutlined />}
                  onClick={() => navigate('/sites/new')}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="300px">
          <Input
            prefix={<SearchOutlined />}
            placeholder="Tim site name..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            allowClear
          />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 100 }}
                  onChange={(v) => setMien(v)}>
            {['MB', 'MT', 'MN'].map((m) =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
      </Row>

      <Table
        columns={columns}
        dataSource={sites}
        rowKey="id"
        loading={loading}
        size="small"
        scroll={{ x: scrollX, y: 600 }}
        pagination={{ pageSize: 50, showTotal: (t) => `${t} sites`, showSizeChanger: true }}
        bordered
      />
    </div>
  )
}