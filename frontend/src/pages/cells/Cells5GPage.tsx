import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber, Tooltip,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { cells5gApi } from '@/api/cells'
import { exportCells5G } from '@/api/export'
import type { Cell5G, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'
import { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'

export default function Cells5GPage() {
  const [data,        setData]        = useState<Cell5G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [exporting,   setExporting]   = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell5G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map((c) => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map((c) => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells5gApi.list({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined, limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then(setAntennaList)
  }, [search, mien, tinh, vendor])

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportCells5G({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined,
      })
      message.success(`Xuat Excel thanh cong (${data.length} cells)`)
    } catch (e: any) {
      message.error(e?.message || 'Xuat that bai')
    } finally { setExporting(false) }
  }

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find((s) => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const handleAntennaSelect = (antennaName: string) => {
    const ant = antennaList.find((a) => a.name === antennaName)
    if (!ant) return
    form.setFieldsValue({ loai_anten: ant.name })
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell5G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await cells5gApi.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await cells5gApi.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Loi') }
  }

  const handleDelete = async (id: number) => {
    await cells5gApi.remove(id); message.success('Da xoa'); load()
  }

  const columns: ColumnsType<Cell5G> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 80,
      render: (_: unknown, r: Cell5G) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa cell nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Mien',      dataIndex: 'mien',      fixed: 'left', width: 70  },
    { title: 'Tinh',      dataIndex: 'tinh',      fixed: 'left', width: 160 },
    { title: 'Phuong xa', dataIndex: 'phuong_xa',               width: 160 },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 240,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 240,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',            dataIndex: 'moran',            width: 120 },
    { title: 'Lat',              dataIndex: 'lat',              width: 110 },
    { title: 'Long',             dataIndex: 'long',             width: 110 },
    { title: 'Vung phu song',    dataIndex: 'vung_phu_song',    width: 120 },
    { title: 'Vendor',           dataIndex: 'vendor',           width: 100 },
    { title: 'Do cao anten',     dataIndex: 'do_cao_anten',     width: 120 },
    { title: 'Azimuth',          dataIndex: 'azimuth',          width: 90  },
    { title: 'M-tilt',           dataIndex: 'm_tilt',           width: 80  },
    { title: 'E-Tilt',           dataIndex: 'e_tilt',           width: 80  },
    { title: 'Total Tilt',       dataIndex: 'total_tilt',       width: 100 },
    { title: 'Loai Anten',       dataIndex: 'loai_anten',       width: 250,
      ellipsis: { showTitle: true } },
    { title: 'Baseband',         dataIndex: 'baseband',         width: 120 },
    { title: 'RF',               dataIndex: 'rf',               width: 100 },
    { title: 'Cell ID',          dataIndex: 'cell_id',          width: 100 },
    { title: 'NR-ARFCN',         dataIndex: 'nr_arfcn',         width: 100 },
    { title: 'PCI',              dataIndex: 'pci',              width: 80  },
    { title: 'Root Sequence ID', dataIndex: 'root_sequence_id', width: 150 },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 5G</Typography.Title>
        <Space>
          <Tooltip title="Xuat du lieu hien tai ra Excel">
            <Button icon={<DownloadOutlined />} loading={exporting}
                    onClick={handleExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>
              Xuat Excel ({data.length})
            </Button>
          </Tooltip>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tim cell / site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 90 }}
                  value={mien} onChange={setMien}>
            {['MB','MT','MN'].map((m) =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select placeholder="Tinh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(i, o) =>
                    String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map((t) =>
              <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select placeholder="Vendor" allowClear style={{ width: '100%' }}
                  value={vendor} onChange={setVendor}>
            {vendorOptions.map((v) =>
              <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => {
            setSearch(''); setMien(undefined)
            setTinh(undefined); setVendor(undefined)
          }}>
            Xoa loc
          </Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading}
             size="small" scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} cells`,
                           showSizeChanger: true }} />

      <Modal title={editing ? 'Chinh sua Cell 5G' : 'Them Cell 5G moi'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={800} okText="Luu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: true }]}>
                <Select showSearch optionFilterProp="children" allowClear
                        placeholder="Chon site..." onChange={handleSiteSelect}
                        filterOption={(i, o) =>
                          String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {sites.map((s) =>
                    <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name" label="Site Name (tu dong dien)">
                <Input readOnly style={{ background: '#f5f5f5' }} />
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
              <Form.Item name="lat" label="Lat (8.33 – 23.39)"
                         rules={[{ validator: latValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5}
                             placeholder="8.33 – 23.39" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="long" label="Long (102.14 – 109.47)"
                         rules={[{ validator: lonValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5}
                             placeholder="102.14 – 109.47" />
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
                  {['Ericsson','Nokia','Huawei','ZTE','Samsung'].map((v) =>
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
              <Form.Item name="azimuth" label="Azimuth (0 – 359)"
                         rules={[{ validator: azimuthValidator }]}>
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
            <Col span={24}>
              <Form.Item name="loai_anten" label="Loai Anten">
                <Select showSearch allowClear placeholder="Chon loai anten..."
                        onChange={handleAntennaSelect}
                        filterOption={(i, o) =>
                          String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {antennaList.map((a) =>
                    <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="baseband" label="Baseband"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="rf" label="RF"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="nr_arfcn" label="NR-ARFCN"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="pci" label="PCI"><Input /></Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="root_sequence_id" label="Root Sequence ID">
                <Input />
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
          </Row>
        </Form>
      </Modal>

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Cell 5G tu Excel"
        templateKey="cell-5g"
        dryRunFn={cells5gApi.dryRunExcel}
        importFn={cells5gApi.importExcel}
        onSuccess={load}
      />
    </div>
  )
}
