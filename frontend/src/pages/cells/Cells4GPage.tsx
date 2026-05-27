import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, Upload, message, Row, Col,
  Modal, Form, InputNumber,
} from 'antd'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { cells4gApi } from '@/api/cells'
import type { Cell4G } from '@/types'
import { getVendors } from '@/api/report'
import { getSites } from '@/api/sites'
import type { Site } from '@/types'

export default function Cells4GPage() {
  const [data,    setData]    = useState<Cell4G[]>([])
  const [loading, setLoading] = useState(false)
  const [search,  setSearch]  = useState('')
  const [vendor,  setVendor]  = useState<string | undefined>()
  const [vendors, setVendors] = useState<string[]>([])
  const [sites,   setSites]   = useState<Site[]>([])
  const [modalOpen, setModalOpen] = useState(false)
  const [editing,   setEditing]   = useState<Cell4G | null>(null)
  const [form] = Form.useForm()

  const load = async () => {
    setLoading(true)
    try { setData(await cells4gApi.list({ search, vendor, limit: 500 })) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getVendors().then((rows: any[]) => {
      const v = new Set<string>()
      rows.forEach((r: any) => { if (r.vendor_4g) v.add(r.vendor_4g) })
      setVendors([...v])
    })
    getSites({ limit: 2000 }).then(setSites)
  }, [search, vendor])

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell4G) => {
    setEditing(r); form.setFieldsValue(r); setModalOpen(true)
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
    const res = await cells4gApi.importExcel(file)
    message.success(`Da nhap ${res.created} cell`)
    if (res.errors?.length) message.warning(`${res.errors.length} loi`)
    load()
    return false
  }

  const columns = [
    { title: 'Site Name',  dataIndex: 'site_name',  width: 130 },
    { title: 'Cell Name',  dataIndex: 'cell_name',  width: 130 },
    { title: 'Vendor',     dataIndex: 'vendor',     width: 100 },
    { title: 'Azimuth',    dataIndex: 'azimuth',    width: 80  },
    { title: 'Do cao anten', dataIndex: 'do_cao_anten', width: 110 },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag>{v}</Tag> : '-' },
    { title: 'Vung phu', dataIndex: 'vung_phu_song', width: 90 },
    { title: "PCI", dataIndex: "pci", width: 80 },
    { title: "EARFCN", dataIndex: "earfcn", width: 90 },
    {
      title: 'Hanh dong', width: 100, fixed: 'right' as const,
      render: (_: unknown, r: Cell4G) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 4G</Typography.Title>
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

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading}
             size="small" scroll={{ x: 900 }}
             pagination={{ pageSize: 50, showTotal: (t) => `${t} cells` }} />

      <Modal title={editing ? 'Chinh sua Cell' : 'Them Cell moi'}
             open={modalOpen} onOk={handleSave}
             onCancel={() => setModalOpen(false)}
             width={720} okText="Luu">
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: true }]}>
                <Select showSearch optionFilterProp="children"
                  filterOption={(input, option) =>
                    String(option?.children ?? '')
                      .toLowerCase().includes(input.toLowerCase())}>
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
            <Col span={12}>
              <Form.Item name="vendor" label="Vendor">
                <Select allowClear>
                  {vendors.map((v) =>
                    <Select.Option key={v} value={v}>{v}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="azimuth" label="Azimuth">
                <InputNumber style={{ width:'100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="do_cao_anten" label="Do cao anten">
                <InputNumber style={{ width:'100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="m_tilt" label="M-Tilt">
                <InputNumber style={{ width:'100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="e_tilt" label="E-Tilt">
                <InputNumber style={{ width:'100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2','4x4','8x8'].map((m) =>
                    <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
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
            <Col span={8}><Form.Item name="pci" label="PCI"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="earfcn" label="EARFCN"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="root_sequence_id" label="Root Seq ID"><Input /></Form.Item></Col>
          </Row>
        </Form>
      </Modal>
    </div>
  )
}
