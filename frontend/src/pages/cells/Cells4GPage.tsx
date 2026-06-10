import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, Upload, message, Row, Col,
  Modal, Form, InputNumber, Spin,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined, LoadingOutlined,
} from '@ant-design/icons'
import { cells4gApi } from '@/api/cells'
import type { Cell4G } from '@/types'
import { getSites } from '@/api/sites'
import type { Site } from '@/types'

export default function Cells4GPage() {
  const [data,      setData]      = useState<Cell4G[]>([])
  const [loading,   setLoading]   = useState(false)
  const [importing, setImporting] = useState(false)
  const [search,    setSearch]    = useState('')
  const [mien,      setMien]      = useState<string | undefined>()
  const [tinh,      setTinh]      = useState<string | undefined>()
  const [vendor,    setVendor]    = useState<string | undefined>()
  const [sites,     setSites]     = useState<Site[]>([])
  const [modalOpen, setModalOpen] = useState(false)
  const [editing,   setEditing]   = useState<Cell4G | null>(null)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map(c => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map(c => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells4gApi.list({
        search: search || undefined,
        mien:   mien   || undefined,
        tinh:   tinh   || undefined,
        vendor: vendor || undefined,
        limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
  }, [search, mien, tinh, vendor])

  const openCreate = () => {
    setEditing(null)
    form.resetFields()
    setModalOpen(true)
  }

  const openEdit = (r: Cell4G) => {
    setEditing(r)
    form.setFieldsValue(r)
    setModalOpen(true)
  }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await cells4gApi.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await cells4gApi.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false)
      load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Loi')
    }
  }

  const handleDelete = async (id: number) => {
    await cells4gApi.remove(id)
    message.success('Da xoa')
    load()
  }

  const handleImport = async (file: File) => {
    setImporting(true)
    try {
      const res = await cells4gApi.importExcel(file)
      const msgs: string[] = []
      if (res.created > 0)            msgs.push(`Tao moi: ${res.created} cell`)
      if (res.updated > 0)            msgs.push(`Cap nhat: ${res.updated} cell`)
      if (res.sites_auto_created > 0) msgs.push(`Tu dong tao: ${res.sites_auto_created} site`)
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
      message.error(e.response?.data?.detail || 'Import that bai')
    } finally {
      setImporting(false)
    }
    return false
  }

  const columns: ColumnsType<Cell4G> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Cell4G) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa cell nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    {
      title: 'Mien', dataIndex: 'mien', fixed: 'left', width: 70,
      sorter: (a, b) => (a.mien || '').localeCompare(b.mien || ''),
    },
    {
      title: 'Tinh', dataIndex: 'tinh', fixed: 'left', width: 130,
      sorter: (a, b) => (a.tinh || '').localeCompare(b.tinh || ''),
    },
    {
      title: 'Phuong xa', dataIndex: 'phuong_xa', width: 130,
      sorter: (a, b) => (a.phuong_xa || '').localeCompare(b.phuong_xa || ''),
    },
    {
      title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 130,
      sorter: (a, b) => (a.site_name || '').localeCompare(b.site_name || ''),
      render: (v: string) => <strong>{v}</strong>,
    },
    {
      title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 130,
      sorter: (a, b) => (a.cell_name || '').localeCompare(b.cell_name || ''),
      render: (v: string) => <strong>{v}</strong>,
    },
    {
      title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      sorter: (a, b) => (a.cell_vip || '').localeCompare(b.cell_vip || ''),
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-',
    },
    {
      title: 'MORAN', dataIndex: 'moran', width: 120,
      sorter: (a, b) => (a.moran || '').localeCompare(b.moran || ''),
    },
    {
      title: 'Lat', dataIndex: 'lat', width: 110,
      sorter: (a, b) => (a.lat || 0) - (b.lat || 0),
    },
    {
      title: 'Long', dataIndex: 'long', width: 110,
      sorter: (a, b) => (a.long || 0) - (b.long || 0),
    },
    {
      title: 'Vung phu song', dataIndex: 'vung_phu_song', width: 120,
      sorter: (a, b) => (a.vung_phu_song || '').localeCompare(b.vung_phu_song || ''),
    },
    {
      title: 'Vendor', dataIndex: 'vendor', width: 100,
      sorter: (a, b) => (a.vendor || '').localeCompare(b.vendor || ''),
    },
    {
      title: 'Do cao anten', dataIndex: 'do_cao_anten', width: 120,
      sorter: (a, b) => (a.do_cao_anten || 0) - (b.do_cao_anten || 0),
    },
    {
      title: 'Azimuth', dataIndex: 'azimuth', width: 90,
      sorter: (a, b) => (a.azimuth || 0) - (b.azimuth || 0),
    },
    {
      title: 'M-tilt', dataIndex: 'm_tilt', width: 80,
      sorter: (a, b) => (a.m_tilt || 0) - (b.m_tilt || 0),
    },
    {
      title: 'E-Tilt', dataIndex: 'e_tilt', width: 80,
      sorter: (a, b) => (a.e_tilt || 0) - (b.e_tilt || 0),
    },
    {
      title: 'Total Tilt', dataIndex: 'total_tilt', width: 100,
      sorter: (a, b) => (a.total_tilt || 0) - (b.total_tilt || 0),
    },
    { title: 'Loai Anten',      dataIndex: 'loai_anten',      width: 180 },
    { title: 'Chung anten',     dataIndex: 'chung_anten',     width: 120 },
    { title: 'Baseband',        dataIndex: 'baseband',        width: 120 },
    { title: 'RF',              dataIndex: 'rf',              width: 100 },
    {
      title: 'Cell ID', dataIndex: 'cell_id', width: 100,
      sorter: (a, b) => (a.cell_id || '').localeCompare(b.cell_id || ''),
    },
    {
      title: 'EARFCN', dataIndex: 'earfcn', width: 90,
      sorter: (a, b) => (a.earfcn || '').localeCompare(b.earfcn || ''),
    },
    {
      title: 'PCI', dataIndex: 'pci', width: 80,
      sorter: (a, b) => (a.pci || '').localeCompare(b.pci || ''),
    },
    {
      title: 'Root Sequence ID', dataIndex: 'root_sequence_id', width: 150,
      sorter: (a, b) => (a.root_sequence_id || '').localeCompare(b.root_sequence_id || ''),
    },
    {
      title: 'MIMO', dataIndex: 'mimo', width: 80,
      sorter: (a, b) => (a.mimo || '').localeCompare(b.mimo || ''),
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-',
    },
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
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 4G</Typography.Title>
        <Space>
          <Upload beforeUpload={handleImport} accept=".xlsx,.xls"
                  showUploadList={false} disabled={importing}>
            <Button icon={importing ? <LoadingOutlined /> : <UploadOutlined />}
                    loading={importing}>
              {importing ? 'Dang import...' : 'Import Excel'}
            </Button>
          </Upload>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input
            prefix={<SearchOutlined />}
            placeholder="Tim cell / site name..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            allowClear
          />
        </Col>
        <Col>
          <Select
            placeholder="Mien" allowClear style={{ width: 90 }}
            value={mien} onChange={setMien}
          >
            {['MB', 'MT', 'MN'].map(m =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select
            placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
            value={tinh} onChange={setTinh}
            filterOption={(input, opt) =>
              String(opt?.children ?? '').toLowerCase().includes(input.toLowerCase())}
          >
            {tinhOptions.map(t =>
              <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select
            placeholder="Vendor" allowClear style={{ width: '100%' }}
            value={vendor} onChange={setVendor}
          >
            {vendorOptions.map(v =>
              <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => {
            setSearch('')
            setMien(undefined)
            setTinh(undefined)
            setVendor(undefined)
          }}>
            Xoa loc
          </Button>
        </Col>
      </Row>

      <Table
        columns={columns}
        dataSource={data}
        rowKey="id"
        loading={loading}
        size="small"
        scroll={{ x: scrollX, y: 600 }}
        bordered
        pagination={{
          pageSize: 50,
          showTotal: (t) => `${t} cells`,
          showSizeChanger: true,
        }}
      />

      <Modal
        title={editing ? 'Chinh sua Cell 4G' : 'Them Cell 4G moi'}
        open={modalOpen}
        onOk={handleSave}
        onCancel={() => setModalOpen(false)}
        width={800}
        okText="Luu"
        destroyOnClose
      >
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site (chon tu danh sach)">
                <Select
                  showSearch optionFilterProp="children" allowClear
                  placeholder="Chon site..."
                  filterOption={(input, option) =>
                    String(option?.children ?? '').toLowerCase()
                      .includes(input.toLowerCase())}
                >
                  {sites.map(s =>
                    <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name" label="Site Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="cell_vip" label="Cell VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="moran" label="MORAN">
                <Select allowClear>
                  <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                  <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="lat" label="Lat">
                <InputNumber style={{ width: '100%' }} precision={5} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="long" label="Long">
                <InputNumber style={{ width: '100%' }} precision={5} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vung_phu_song" label="Vung phu song">
                <Select allowClear>
                  <Select.Option value="Indoor">Indoor</Select.Option>
                  <Select.Option value="Outdoor">Outdoor</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vendor" label="Vendor">
                <Select allowClear>
                  {['Ericsson', 'Nokia', 'Huawei', 'ZTE', 'Samsung'].map(v =>
                    <Select.Option key={v} value={v}>{v}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="do_cao_anten" label="Do cao anten (m)">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="azimuth" label="Azimuth (0-359)">
                <InputNumber style={{ width: '100%' }} min={0} max={359} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="m_tilt" label="M-tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="e_tilt" label="E-Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="total_tilt" label="Total Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="loai_anten" label="Loai Anten">
                <Input />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="chung_anten" label="Chung anten">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="baseband" label="Baseband">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="rf" label="RF">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="cell_id" label="Cell ID">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="earfcn" label="EARFCN">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="pci" label="PCI">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="root_sequence_id" label="Root Sequence ID">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2', '4x4', '8x8'].map(m =>
                    <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>
    </div>
  )
}