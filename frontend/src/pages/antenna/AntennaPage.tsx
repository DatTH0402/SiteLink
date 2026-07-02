import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Popconfirm,
  message, Row, Col, Modal, Form, InputNumber,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import {
  getAntennas, createAntenna, updateAntenna,
  deleteAntenna, dryRunAntennaExcel, importAntennaExcel,
} from '@/api/antenna'
import type { AntennaFull } from '@/types'
import DryRunModal from '@/components/shared/DryRunModal'

export default function AntennaPage() {
  const [data,       setData]       = useState<AntennaFull[]>([])
  const [loading,    setLoading]    = useState(false)
  const [search,     setSearch]     = useState('')
  const [modalOpen,  setModalOpen]  = useState(false)
  const [editing,    setEditing]    = useState<AntennaFull | null>(null)
  const [dryRunOpen, setDryRunOpen] = useState(false)
  const [detailOpen, setDetailOpen] = useState(false)
  const [selected,   setSelected]   = useState<AntennaFull | null>(null)
  const [form] = Form.useForm()

  const load = async () => {
    setLoading(true)
    try {
      setData(await getAntennas({ search: search || undefined, limit: 2000 }))
    } finally { setLoading(false) }
  }

  useEffect(() => { load() }, [search])

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: AntennaFull) => {
    setEditing(r); form.setFieldsValue(r); setModalOpen(true)
  }
  const openDetail = (r: AntennaFull) => { setSelected(r); setDetailOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await updateAntenna(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await createAntenna(values)
        message.success('Tao antenna thanh cong')
      }
      setModalOpen(false); load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Loi')
    }
  }

  const handleDelete = async (id: number) => {
    await deleteAntenna(id); message.success('Da xoa'); load()
  }

  const columns: ColumnsType<AntennaFull> = [
    {
      title: 'Hanh dong', key: 'action', fixed: 'left', width: 100,
      render: (_: unknown, r: AntennaFull) => (
        <Space>
          <Button size="small" onClick={() => openDetail(r)}>Chi tiet</Button>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa antenna nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    { title: 'Name',           dataIndex: 'name',           fixed: 'left', width: 280,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Band',           dataIndex: 'band',           width: 150 },
    { title: 'No of Ports',    dataIndex: 'no_of_ports',    width: 110 },
    { title: 'No of Beam',     dataIndex: 'no_of_beam',     width: 110 },
    { title: 'Horizontal BW',  dataIndex: 'horizontal_bw',  width: 120 },
    { title: 'Vertical BW',    dataIndex: 'vertical_bw',    width: 110 },
    { title: 'Gain',           dataIndex: 'gain',           width: 80  },
    { title: 'Etilt',          dataIndex: 'etilt',          width: 90  },
    { title: 'H (mm)',         dataIndex: 'h',              width: 90  },
    { title: 'W (mm)',         dataIndex: 'w',              width: 90  },
    { title: 'D (mm)',         dataIndex: 'd',              width: 90  },
    { title: 'Weight',         dataIndex: 'weight',         width: 90  },
    { title: 'Connector type', dataIndex: 'connector_type', width: 160 },
    { title: 'Ghi chu',        dataIndex: 'ghi_chu',        width: 200 },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quan ly Antenna</Typography.Title>
        <Space>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="320px">
          <Input prefix={<SearchOutlined />} placeholder="Tim ten antenna..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Button onClick={() => setSearch('')}>Xoa loc</Button>
        </Col>
        <Col>
          <Button onClick={load} loading={loading}>Lam moi</Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading} size="small"
             scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: (t) => `${t} antennas`,
                           showSizeChanger: true }} />

      {/* ── Detail modal ── */}
      <Modal title={selected?.name} open={detailOpen}
             onCancel={() => setDetailOpen(false)} footer={null} width={600}>
        {selected && (
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            {([
              ['Band',           selected.band],
              ['No of Ports',    selected.no_of_ports],
              ['No of Beam',     selected.no_of_beam],
              ['Horizontal BW',  selected.horizontal_bw],
              ['Vertical BW',    selected.vertical_bw],
              ['Gain',           selected.gain],
              ['Etilt',          selected.etilt],
              ['H (mm)',         selected.h],
              ['W (mm)',         selected.w],
              ['D (mm)',         selected.d],
              ['Weight',         selected.weight],
              ['Connector type', selected.connector_type],
              ['Ghi chu',        selected.ghi_chu],
            ] as [string, unknown][]).map(([label, val]) => (
              <tr key={label} style={{ borderBottom: '1px solid #f0f0f0' }}>
                <td style={{ padding: '6px 12px', fontWeight: 600,
                             width: 160, color: '#666' }}>{label}</td>
                <td style={{ padding: '6px 12px' }}>{String(val ?? '-')}</td>
              </tr>
            ))}
          </table>
        )}
      </Modal>

      {/* ── Create / Edit modal ── */}
      <Modal title={editing ? 'Chinh sua Antenna' : 'Them Antenna moi'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={700} okText="Luu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={24}>
              <Form.Item name="name" label="Name (dinh danh duy nhat)"
                         rules={[{ required: true, message: 'Vui long nhap ten antenna' }]}>
                <Input disabled={Boolean(editing)} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="band" label="Band">
                <Input placeholder="vd: 900-1800-2100" />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="no_of_ports" label="No of Ports">
                <InputNumber style={{ width: '100%' }} min={1} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="no_of_beam" label="No of Beam">
                <InputNumber style={{ width: '100%' }} min={1} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="horizontal_bw" label="Horizontal BW">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vertical_bw" label="Vertical BW">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="gain" label="Gain (dBi)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="etilt" label="Etilt range">
                <Input placeholder="vd: 0-10" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="h" label="H – Height (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="w" label="W – Width (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="d" label="D – Depth (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="weight" label="Weight (kg)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="connector_type" label="Connector type">
                <Input />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="ghi_chu" label="Ghi chu">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Antenna tu Excel"
        templateKey={undefined}
        dryRunFn={dryRunAntennaExcel}
        importFn={importAntennaExcel}
        onSuccess={load}
      />
    </div>
  )
}
