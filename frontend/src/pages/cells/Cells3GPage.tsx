import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, Upload, message, Row, Col,
  Modal, Form, InputNumber,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { cells3gApi } from '@/api/cells'
import type { Cell3G } from '@/types'
import { getVendors } from '@/api/report'
import { getSites } from '@/api/sites'
import type { Site } from '@/types'

export default function Cells3GPage() {
  const [data,    setData]    = useState<Cell3G[]>([])
  const [loading, setLoading] = useState(false)
  const [search,  setSearch]  = useState('')
  const [vendor,  setVendor]  = useState<string | undefined>()
  const [vendors, setVendors] = useState<string[]>([])
  const [sites,   setSites]   = useState<Site[]>([])
  const [modalOpen, setModalOpen] = useState(false)
  const [editing,   setEditing]   = useState<Cell3G | null>(null)
  const [form] = Form.useForm()

  const load = async () => {
    setLoading(true)
    try { setData(await cells3gApi.list({ search, vendor, limit: 500 })) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getVendors().then((rows: any[]) => {
      const v = new Set<string>()
      rows.forEach((r: any) => { if (r.vendor_3g) v.add(r.vendor_3g) })
      setVendors([...v])
    })
    getSites({ limit: 2000 }).then(setSites)
  }, [search, vendor])

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell3G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await cells3gApi.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await cells3gApi.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false)
      load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Loi')
    }
  }

  const handleDelete = async (id: number) => {
    await cells3gApi.remove(id)
    message.success('Da xoa')
    load()
  }

  const handleImport = async (file: File) => {
    try {
      const res = await cells3gApi.importExcel(file)
      if (res.created > 0) message.success(`Da nhap ${res.created} cell`)
      if (res.errors?.length) {
        Modal.error({
          title: `${res.errors.length} dong bi loi`,
          width: 700,
          content: (
            <div style={{ maxHeight: 400, overflowY: 'auto' }}>
              {res.errors.slice(0, 20).map((e: string, i: number) => (
                <div key={i} style={{
                  padding: '4px 0',
                  borderBottom: '1px solid #f0f0f0',
                  fontSize: 12,
                  fontFamily: 'monospace',
                }}>
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

  const columns: ColumnsType<Cell3G> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Cell3G) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    // exact spec column order for 3G
    { title: 'Mien',          dataIndex: 'mien',          fixed: 'left', width: 70  },
    { title: 'Tinh',          dataIndex: 'tinh',          fixed: 'left', width: 130 },
    { title: 'Phuong xa',     dataIndex: 'phuong_xa',     width: 130 },
    { title: 'Site Name',     dataIndex: 'site_name',     fixed: 'left', width: 130,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name',     dataIndex: 'cell_name',     fixed: 'left', width: 130,
      render: (v: string) => <strong>{v}</strong> },
    {
      title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-',
    },
    { title: 'MORAN',         dataIndex: 'moran',         width: 120 },
    { title: 'Lat',           dataIndex: 'lat',           width: 110 },
    { title: 'Long',          dataIndex: 'long',          width: 110 },
    { title: 'Vung phu song', dataIndex: 'vung_phu_song', width: 120 },
    { title: 'Vendor',        dataIndex: 'vendor',        width: 100 },
    { title: 'Do cao anten',  dataIndex: 'do_cao_anten',  width: 120 },
    { title: 'Azimuth',       dataIndex: 'azimuth',       width: 90  },
    { title: 'M-tilt',        dataIndex: 'm_tilt',        width: 80  },
    { title: 'E-Tilt',        dataIndex: 'e_tilt',        width: 80  },
    { title: 'Total Tilt',    dataIndex: 'total_tilt',    width: 100 },
    { title: 'Loai Anten',    dataIndex: 'loai_anten',    width: 180 },
    { title: 'Chung anten',   dataIndex: 'chung_anten',   width: 120 },
    { title: 'Baseband',      dataIndex: 'baseband',      width: 120 },
    { title: 'RF',            dataIndex: 'rf',            width: 100 },
    { title: 'Cell ID',       dataIndex: 'cell_id',       width: 100 },
    { title: 'ARFCN',         dataIndex: 'arfcn',         width: 90  },
    { title: 'PSC',           dataIndex: 'psc',           width: 80  },
    {
      title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-',
    },
  ]

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 3G</Typography.Title>
        <Space>
          <Upload beforeUpload={handleImport} accept=".xlsx,.xls" showUploadList={false}>
            <Button icon={<UploadOutlined />}>Import Excel</Button>
          </Upload>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="280px">
          <Input prefix={<SearchOutlined />} placeholder="Tim cell/site..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Vendor" allowClear style={{ width: 130 }}
                  onChange={(v) => setVendor(v)}>
            {vendors.map((v) =>
              <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
      </Row>

      <Table
        columns={columns} dataSource={data} rowKey="id" loading={loading}
        size="small" scroll={{ x: scrollX, y: 600 }} bordered
        pagination={{ pageSize: 50, showTotal: (t) => `${t} cells`, showSizeChanger: true }}
      />

      <Modal title={editing ? 'Chinh sua Cell 3G' : 'Them Cell 3G moi'}
             open={modalOpen} onOk={handleSave}
             onCancel={() => setModalOpen(false)}
             width={800} okText="Luu">
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: true }]}>
                <Select showSearch optionFilterProp="children"
                  filterOption={(input, option) =>
                    String(option?.children ?? '').toLowerCase().includes(input.toLowerCase())}>
                  {sites.map((s) =>
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
                  {vendors.map((v) =>
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
              <Form.Item name="azimuth" label="Azimuth">
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
              <Form.Item name="arfcn" label="ARFCN">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="psc" label="PSC">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2', '4x4', '8x8'].map((m) =>
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