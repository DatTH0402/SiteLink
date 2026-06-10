import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, Upload, message, Row, Col, Modal, Spin,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined, LoadingOutlined,
} from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { getSites, deleteSite, importSitesExcel } from '@/api/sites'
import type { Site } from '@/types'

const boolCell = (v: boolean) => v ? <Tag color="green">x</Tag> : <Tag color="default">-</Tag>

export default function SitesPage() {
  const navigate    = useNavigate()
  const [sites,     setSites]     = useState<Site[]>([])
  const [loading,   setLoading]   = useState(false)
  const [importing, setImporting] = useState(false)
  const [search,    setSearch]    = useState('')
  const [mien,      setMien]      = useState<string | undefined>()
  const [tinh,      setTinh]      = useState<string | undefined>()

  const tinhOptions = [...new Set(sites.map(s => s.tinh).filter((t): t is string => Boolean(t)))].sort()

  const load = async () => {
    setLoading(true)
    try {
      setSites(await getSites({
        search: search || undefined,
        mien:   mien   || undefined,
        tinh:   tinh   || undefined,
        limit: 500,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => { load() }, [search, mien, tinh])

  const handleDelete = async (id: number) => {
    await deleteSite(id)
    message.success('Da xoa site')
    load()
  }

  const handleImport = async (file: File) => {
    setImporting(true)
    try {
      const res = await importSitesExcel(file)
      const msgs: string[] = []
      if (res.created > 0) msgs.push(`Tao moi: ${res.created} site`)
      if (res.updated > 0) msgs.push(`Cap nhat: ${res.updated} site`)
      if (msgs.length > 0) message.success(msgs.join(' | '))
      if (res.errors?.length) {
        Modal.error({
          title: `${res.errors.length} dong bi loi`,
          width: 700,
          content: (
            <div style={{ maxHeight: 400, overflowY: 'auto' }}>
              {res.errors.slice(0, 20).map((e: string, i: number) => (
                <div key={i} style={{
                  padding: '4px 0', borderBottom: '1px solid #f0f0f0',
                  fontSize: 12, fontFamily: 'monospace',
                }}>{e}</div>
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
      if (res.created > 0 || res.updated > 0) load()
    } catch (e: any) {
      message.error((e as any).response?.data?.detail || 'Import that bai')
    } finally {
      setImporting(false)
    }
    return false
  }

  const columns: ColumnsType<Site> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
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
    { title: 'Mien',           dataIndex: 'mien',           fixed: 'left', width: 70,
      sorter: (a: Site, b: Site) => (a.mien||'').localeCompare(b.mien||'') },
    { title: 'Tinh',           dataIndex: 'tinh',           fixed: 'left', width: 130,
      sorter: (a: Site, b: Site) => (a.tinh||'').localeCompare(b.tinh||'') },
    { title: 'Phuong xa',      dataIndex: 'phuong_xa',      width: 130,
      sorter: (a: Site, b: Site) => (a.phuong_xa||'').localeCompare(b.phuong_xa||'') },
    { title: 'Site name (cu)', dataIndex: 'site_name_cu',   width: 130,
      sorter: (a: Site, b: Site) => (a.site_name_cu||'').localeCompare(b.site_name_cu||'') },
    { title: 'Site name',      dataIndex: 'site_name',      fixed: 'left', width: 130,
      sorter: (a: Site, b: Site) => (a.site_name||'').localeCompare(b.site_name||''),
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Site VIP',       dataIndex: 'site_vip',       width: 90,
      sorter: (a: Site, b: Site) => (a.site_vip||'').localeCompare(b.site_vip||''),
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'Lat',            dataIndex: 'lat',            width: 110,
      sorter: (a: Site, b: Site) => (a.lat||0) - (b.lat||0) },
    { title: 'Long',           dataIndex: 'long',           width: 110,
      sorter: (a: Site, b: Site) => (a.long||0) - (b.long||0) },
    { title: 'Tram 2G',        dataIndex: 'tram_2g',        width: 80,  render: boolCell },
    { title: 'Tram 3G',        dataIndex: 'tram_3g',        width: 80,  render: boolCell },
    { title: 'Tram 4G',        dataIndex: 'tram_4g',        width: 80,  render: boolCell },
    { title: 'Tram 5G',        dataIndex: 'tram_5g',        width: 80,  render: boolCell },
    { title: 'Repeater',       dataIndex: 'repeater',       width: 90,  render: boolCell },
    { title: 'Booster',        dataIndex: 'booster',        width: 85,  render: boolCell },
    { title: 'Node truyen dan only', dataIndex: 'node_truyen_dan_only', width: 160, render: boolCell },
    { title: 'Phan loai tram', dataIndex: 'phan_loai_tram', width: 180,
      sorter: (a: Site, b: Site) => (a.phan_loai_tram||'').localeCompare(b.phan_loai_tram||'') },
    { title: 'Tram phu song TSCA', dataIndex: 'tram_phu_song_tsca', width: 160 },
    { title: 'MORAN 3G',       dataIndex: 'moran_3g',       width: 120 },
    { title: 'MORAN 4G',       dataIndex: 'moran_4g',       width: 120 },
    { title: 'MORAN 5G',       dataIndex: 'moran_5g',       width: 120 },
    { title: 'Ma PTM',         dataIndex: 'ma_ptm',         width: 120,
      sorter: (a: Site, b: Site) => (a.ma_ptm||'').localeCompare(b.ma_ptm||'') },
    { title: 'Do cao dinh cot anten (m)', dataIndex: 'do_cao_dinh_cot_anten', width: 190,
      sorter: (a: Site, b: Site) => (a.do_cao_dinh_cot_anten||0)-(b.do_cao_dinh_cot_anten||0) },
    { title: 'Do cao cot anten mat san (m)', dataIndex: 'do_cao_cot_anten', width: 210,
      sorter: (a: Site, b: Site) => (a.do_cao_cot_anten||0)-(b.do_cao_cot_anten||0) },
    { title: 'Dia chi',        dataIndex: 'dia_chi',        width: 200 },
    { title: 'Ghi chu',        dataIndex: 'ghi_chu',        width: 200 },
  ]

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      {importing && (
        <div style={{
          position: 'fixed', top: 0, left: 0, right: 0, bottom: 0,
          background: 'rgba(0,0,0,0.45)', zIndex: 9999,
          display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center',
        }}>
          <Spin indicator={<LoadingOutlined style={{ fontSize: 48, color: '#fff' }} spin />} />
          <div style={{ color: '#fff', marginTop: 16, fontSize: 16 }}>
            Dang xu ly import Excel, vui long cho...
          </div>
        </div>
      )}

      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quan ly Site</Typography.Title>
        <Space>
          <Upload beforeUpload={handleImport} accept=".xlsx,.xls"
                  showUploadList={false} disabled={importing}>
            <Button icon={importing ? <LoadingOutlined /> : <UploadOutlined />}
                    loading={importing}>
              {importing ? 'Dang import...' : 'Import Excel'}
            </Button>
          </Upload>
          <Button type="primary" icon={<PlusOutlined />}
                  onClick={() => navigate('/sites/new')}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map(m =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="200px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(input, opt) =>
                    String(opt?.children ?? '').toLowerCase().includes(input.toLowerCase())}>
            {tinhOptions.map(t =>
              <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien(undefined); setTinh(undefined) }}>
            Xoa loc
          </Button>
        </Col>
      </Row>

      <Table
        columns={columns} dataSource={sites} rowKey="id"
        loading={loading} size="small"
        scroll={{ x: scrollX, y: 600 }} bordered
        pagination={{ pageSize: 50, showTotal: t => `${t} sites`, showSizeChanger: true }}
      />
    </div>
  )
}
