import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Popconfirm,
  message, Row, Col, Modal, Form, InputNumber, Tooltip,
  Switch, Upload, Tag,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
  FilePdfOutlined, PaperClipOutlined, DeleteFilled,
} from '@ant-design/icons'
import {
  getAntennas, createAntenna, updateAntenna,
  deleteAntenna, dryRunAntennaExcel, importAntennaExcel,
  uploadAntennaSpecFile, deleteAntennaSpecFile, downloadAntennaSpecFile,
} from '@/api/antenna'
import { exportAntennas } from '@/api/export'
import type { AntennaFull } from '@/types'
import DryRunModal from '@/components/shared/DryRunModal'

// ── helpers ───────────────────────────────────────────────────────────────────

/** Sort so "CHƯA XÁC ĐỊNH" entries float to the top. */
function sortAntennas(list: AntennaFull[]): AntennaFull[] {
  return [...list].sort((a, b) => {
    const aU = a.name.toUpperCase()
    const bU = b.name.toUpperCase()
    const aFirst =
      aU.includes('CHƯA XÁC ĐỊNH') || aU.includes('CHUA XAC DINH')
    const bFirst =
      bU.includes('CHƯA XÁC ĐỊNH') || bU.includes('CHUA XAC DINH')
    if (aFirst && !bFirst) return -1
    if (!aFirst && bFirst) return  1
    return 0
  })
}

// ── component ─────────────────────────────────────────────────────────────────

export default function AntennaPage() {
  const [data,          setData]          = useState<AntennaFull[]>([])
  const [loading,       setLoading]       = useState(false)
  const [exporting,     setExporting]     = useState(false)
  const [search,        setSearch]        = useState('')
  const [modalOpen,     setModalOpen]     = useState(false)
  const [editing,       setEditing]       = useState<AntennaFull | null>(null)
  const [dryRunOpen,    setDryRunOpen]    = useState(false)
  const [detailOpen,    setDetailOpen]    = useState(false)
  const [selected,      setSelected]      = useState<AntennaFull | null>(null)
  const [specUploading, setSpecUploading] = useState<number | null>(null)
  const [specDeleting,  setSpecDeleting]  = useState<number | null>(null)
  const [form] = Form.useForm()

  // ── data loading ────────────────────────────────────────────────────────────

  const load = async () => {
    setLoading(true)
    try {
      const params: Record<string, unknown> = { limit: 2000 }
      if (search) params.search = search
      setData(sortAntennas(await getAntennas(params)))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [search])

  // ── export ──────────────────────────────────────────────────────────────────

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportAntennas({ search: search || undefined })
      message.success(`Xuất Excel thành công (${data.length} antennas)`)
    } catch (e: any) {
      message.error(e?.message || 'Xuất thất bại')
    } finally {
      setExporting(false)
    }
  }

  // ── modal helpers ───────────────────────────────────────────────────────────

  const openCreate = () => {
    setEditing(null)
    form.resetFields()
    setModalOpen(true)
  }

  const openEdit = (r: AntennaFull) => {
    setEditing(r)
    form.setFieldsValue(r)
    setModalOpen(true)
  }

  const openDetail = (r: AntennaFull) => {
    setSelected(r)
    setDetailOpen(true)
  }

  // ── CRUD handlers ───────────────────────────────────────────────────────────

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await updateAntenna(editing.id, values)
        message.success('Cập nhật thành công')
      } else {
        await createAntenna(values)
        message.success('Tạo antenna thành công')
      }
      setModalOpen(false)
      load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Lỗi')
    }
  }

  const handleDelete = async (id: number) => {
    await deleteAntenna(id)
    message.success('Đã xóa')
    load()
  }

  // ── spec-file handlers ──────────────────────────────────────────────────────

  const handleSpecUpload = async (file: File, antenna: AntennaFull) => {
    if (file.type !== 'application/pdf') {
      message.error('Chỉ chấp nhận file PDF')
      return false
    }
    setSpecUploading(antenna.id)
    try {
      const updated = await uploadAntennaSpecFile(antenna.id, file)
      setData((prev) => prev.map((a) => (a.id === updated.id ? updated : a)))
      if (selected?.id === updated.id) setSelected(updated)
      message.success('Tải lên file spec thành công')
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Tải lên thất bại')
    } finally {
      setSpecUploading(null)
    }
    return false
  }

  const handleSpecDelete = async (antenna: AntennaFull) => {
    setSpecDeleting(antenna.id)
    try {
      const updated = await deleteAntennaSpecFile(antenna.id)
      setData((prev) => prev.map((a) => (a.id === updated.id ? updated : a)))
      if (selected?.id === updated.id) setSelected(updated)
      message.success('Đã xoá file spec')
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Xóa thất bại')
    } finally {
      setSpecDeleting(null)
    }
  }

  const handleSpecDownload = async (antenna: AntennaFull) => {
    try {
      await downloadAntennaSpecFile(
        antenna.id,
        antenna.spec_file_name || 'spec.pdf',
      )
    } catch (e: any) {
      message.error(e?.message || 'Tải xuống thất bại')
    }
  }

  // ── table columns ───────────────────────────────────────────────────────────

  const columns: ColumnsType<AntennaFull> = [
    {
      title: 'Hành động',
      key: 'action',
      fixed: 'left',
      width: 160,
      render: (_: unknown, r: AntennaFull) => (
        <Space size={4} wrap>
          <Button size="small" onClick={() => openDetail(r)}>Chi tiết</Button>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xóa antenna này?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
    {
      title: 'Name', dataIndex: 'name', fixed: 'left', width: 280,
      render: (v: string) => <strong>{v}</strong>,
    },
    {
      title: '5G AAU', dataIndex: 'is_5g_aau', width: 85,
      render: (v: boolean) =>
        v ? <Tag color="purple">5G AAU</Tag> : <Tag color="default">-</Tag>,
    },
    { title: 'Band',           dataIndex: 'band',           width: 150 },
    { title: 'No of Ports',    dataIndex: 'no_of_ports',    width: 110 },
    { title: 'No of Beam',     dataIndex: 'no_of_beam',     width: 110 },
    { title: 'Horizontal BW',  dataIndex: 'horizontal_bw',  width: 120 },
    { title: 'Vertical BW',    dataIndex: 'vertical_bw',    width: 110 },
    { title: 'Gain',           dataIndex: 'gain',           width: 80  },
    { title: 'Etilt',          dataIndex: 'etilt',          width: 90  },
    { title: 'H (mm)',         dataIndex: 'h',              width: 80  },
    { title: 'W (mm)',         dataIndex: 'w',              width: 80  },
    { title: 'D (mm)',         dataIndex: 'd',              width: 80  },
    { title: 'Weight',         dataIndex: 'weight',         width: 80  },
    { title: 'Connector type', dataIndex: 'connector_type', width: 150 },
    {
      title: 'Specification (PDF)',
      key: 'spec_file',
      width: 230,
      render: (_: unknown, r: AntennaFull) => (
        <Space size={4} wrap>
          {r.spec_file_name ? (
            <>
              <Tooltip title={r.spec_file_name}>
                <Button
                  size="small"
                  type="link"
                  icon={<FilePdfOutlined style={{ color: '#f5222d' }} />}
                  onClick={() => handleSpecDownload(r)}
                  style={{
                    padding: 0, maxWidth: 130,
                    overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                  }}
                >
                  {r.spec_file_name.length > 16
                    ? r.spec_file_name.slice(0, 16) + '…'
                    : r.spec_file_name}
                </Button>
              </Tooltip>
              <Popconfirm
                title="Xóa file spec này?"
                onConfirm={() => handleSpecDelete(r)}
              >
                <Button
                  size="small" danger icon={<DeleteFilled />}
                  loading={specDeleting === r.id}
                />
              </Popconfirm>
            </>
          ) : (
            <Upload
              accept=".pdf"
              showUploadList={false}
              beforeUpload={(file) => handleSpecUpload(file, r)}
            >
              <Button
                size="small"
                icon={<PaperClipOutlined />}
                loading={specUploading === r.id}
              >
                Đính kèm PDF
              </Button>
            </Upload>
          )}
        </Space>
      ),
    },
    { title: 'Ghi chu', dataIndex: 'ghi_chu', width: 200 },
  ]

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  // ── render ──────────────────────────────────────────────────────────────────

  return (
    <div>
      {/* ── page header ── */}
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>
          Thư viện Antenna
        </Typography.Title>
        <Space>
          <Tooltip title="Xuất dữ liệu hiện tại ra Excel">
            <Button
              icon={<DownloadOutlined />}
              loading={exporting}
              onClick={handleExport}
              style={{ borderColor: '#52c41a', color: '#52c41a' }}
            >
              Xuất Excel ({data.length})
            </Button>
          </Tooltip>
          {/* ── Import button – now opens the full DryRunModal ── */}
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>
            Import Excel
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Thêm mới
          </Button>
        </Space>
      </Row>

      {/* ── filter bar ── */}
      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="320px">
          <Input
            prefix={<SearchOutlined />}
            placeholder="Tìm tên antenna..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            allowClear
          />
        </Col>
        <Col>
          <Button onClick={() => setSearch('')}>Xóa lọc</Button>
        </Col>
        <Col>
          <Button onClick={load} loading={loading}>Làm mới</Button>
        </Col>
      </Row>

      {/* ── main table ── */}
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
          showTotal: (t) => `${t} antennas`,
          showSizeChanger: true,
        }}
      />

      {/* ── Detail modal ── */}
      <Modal
        title={selected?.name}
        open={detailOpen}
        onCancel={() => setDetailOpen(false)}
        footer={
          <Space>
            {selected?.spec_file_name && (
              <Button
                icon={<FilePdfOutlined />}
                type="primary"
                onClick={() => selected && handleSpecDownload(selected)}
              >
                Tải Specification PDF
              </Button>
            )}
            <Button onClick={() => setDetailOpen(false)}>Đóng</Button>
          </Space>
        }
        width={620}
      >
        {selected && (
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            {(
              [
                ['5G AAU',         selected.is_5g_aau ? 'Có ✓' : 'Không'],
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
                ['Specification',  selected.spec_file_name || '(chưa đính kèm)'],
                ['Ghi chu',        selected.ghi_chu],
              ] as [string, unknown][]
            ).map(([label, val]) => (
              <tr key={label} style={{ borderBottom: '1px solid #f0f0f0' }}>
                <td style={{
                  padding: '6px 12px', fontWeight: 600,
                  width: 160, color: '#666',
                }}>
                  {label}
                </td>
                <td style={{ padding: '6px 12px' }}>
                  {label === 'Specification' && selected.spec_file_name ? (
                    <Button
                      type="link"
                      icon={<FilePdfOutlined style={{ color: '#f5222d' }} />}
                      onClick={() => handleSpecDownload(selected)}
                      style={{ padding: 0 }}
                    >
                      {selected.spec_file_name}
                    </Button>
                  ) : (
                    String(val ?? '-')
                  )}
                </td>
              </tr>
            ))}
          </table>
        )}
      </Modal>

      {/* ── Create / Edit modal ── */}
      <Modal
        title={editing ? 'Chỉnh sửa Antenna' : 'Thêm Antenna mới'}
        open={modalOpen}
        onOk={handleSave}
        onCancel={() => setModalOpen(false)}
        width={720}
        okText="Lưu"
        destroyOnClose
      >
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={24}>
              <Form.Item
                name="name"
                label="Name (định danh duy nhất)"
                rules={[{ required: true, message: 'Vui lòng nhập tên antenna' }]}
              >
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
            <Col span={6}>
              <Form.Item name="is_5g_aau" label="5G AAU" valuePropName="checked">
                <Switch checkedChildren="Có" unCheckedChildren="Không" />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="horizontal_bw" label="Horizontal BW">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="vertical_bw" label="Vertical BW">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="gain" label="Gain (dBi)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="etilt" label="Etilt range">
                <Input placeholder="vd: 0-10" />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="h" label="H – Height (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="w" label="W – Width (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="d" label="D – Depth (mm)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="weight" label="Weight (kg)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="connector_type" label="Connector type">
                <Input />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="ghi_chu" label="Ghi chú">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>

            {/* Spec file – only shown when editing an existing record */}
            {editing && (
              <Col span={24}>
                <Form.Item label="Specification PDF">
                  {editing.spec_file_name ? (
                    <Space>
                      <Button
                        icon={<FilePdfOutlined style={{ color: '#f5222d' }} />}
                        onClick={() =>
                          downloadAntennaSpecFile(
                            editing.id,
                            editing.spec_file_name!,
                          )
                        }
                      >
                        {editing.spec_file_name}
                      </Button>
                      <Popconfirm
                        title="Xóa file spec?"
                        onConfirm={async () => {
                          const updated = await deleteAntennaSpecFile(editing.id)
                          setEditing(updated)
                          setData((prev) =>
                            prev.map((a) => (a.id === updated.id ? updated : a)),
                          )
                        }}
                      >
                        <Button danger size="small">Xóa file</Button>
                      </Popconfirm>
                    </Space>
                  ) : (
                    <Upload
                      accept=".pdf"
                      showUploadList={false}
                      beforeUpload={async (file) => {
                        const updated = await uploadAntennaSpecFile(
                          editing.id, file,
                        )
                        setEditing(updated)
                        setData((prev) =>
                          prev.map((a) => (a.id === updated.id ? updated : a)),
                        )
                        message.success('Tải lên thành công')
                        return false
                      }}
                    >
                      <Button icon={<PaperClipOutlined />}>
                        Đính kèm file PDF
                      </Button>
                    </Upload>
                  )}
                </Form.Item>
              </Col>
            )}
          </Row>
        </Form>
      </Modal>

      {/* ── DryRunModal – full import wizard with template download ── */}
      <DryRunModal
        open={dryRunOpen}
        onClose={() => setDryRunOpen(false)}
        title="Import Antenna từ Excel"
        templateKey="antenna"
        dryRunFn={dryRunAntennaExcel}
        importFn={importAntennaExcel}
        onSuccess={load}
      />
    </div>
  )
}
