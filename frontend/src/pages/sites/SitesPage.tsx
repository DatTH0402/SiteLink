import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, Upload, message, Row, Col,
} from 'antd'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { getSites, deleteSite, importSitesExcel } from '@/api/sites'
import type { Site } from '@/types'

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
      message.success(`Da nhap ${res.created} site`)
      if (res.errors?.length)
        message.warning(`${res.errors.length} loi - xem console`)
      load()
    } catch {
      message.error('Import that bai')
    }
    return false
  }

  const columns = [
    { title: 'Mien',      dataIndex: 'mien',      width: 70  },
    { title: 'Tinh',      dataIndex: 'tinh',      width: 140 },
    { title: 'Site Name', dataIndex: 'site_name', width: 150,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Lat',  dataIndex: 'lat',  width: 110 },
    { title: 'Long', dataIndex: 'long', width: 110 },
    {
      title: 'Cong nghe', width: 160,
      render: (_: unknown, r: Site) => (
        <Space size={2}>
          {r.tram_2g && <Tag color="default">2G</Tag>}
          {r.tram_3g && <Tag color="blue">3G</Tag>}
          {r.tram_4g && <Tag color="orange">4G</Tag>}
          {r.tram_5g && <Tag color="red">5G</Tag>}
        </Space>
      ),
    },
    { title: 'Loai tram', dataIndex: 'phan_loai_tram', width: 130 },
    { title: 'Ma PTM',    dataIndex: 'ma_ptm',         width: 120 },
    {
      title: 'Hanh dong', width: 110, fixed: 'right' as const,
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
  ]

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
            {['MB','MT','MN'].map((m) =>
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
        scroll={{ x: 1000 }}
        pagination={{ pageSize: 50, showTotal: (t) => `${t} sites` }}
      />
    </div>
  )
}
