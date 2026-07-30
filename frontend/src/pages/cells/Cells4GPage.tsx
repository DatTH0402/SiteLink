import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col, Tooltip,
  Modal, Form, InputNumber,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import type { TableRowSelection } from 'antd/es/table/interface'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { cells4gApi } from '@/api/cells'
import { exportCells4G } from '@/api/export'
import type { Cell4G, Site, AntennaItem, TinhItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList, getTinhList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'
import CellBulkEditModal from '@/components/shared/CellBulkEditModal'
import { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'

const CHUNG_ANTEN_4G = ['4G', '2G/4G', '3G/4G', '2G/3G/4G', '4G/5G']

export default function Cells4GPage() {
  const [data,        setData]        = useState<Cell4G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [exporting,   setExporting]   = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string[]>([])
  const [tinh,        setTinh]        = useState<string[]>([])
  const [vendor,      setVendor]      = useState<string[]>([])
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [tinhList,    setTinhList]    = useState<TinhItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell4G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [selectedIds, setSelectedIds] = useState<number[]>([])
  const [bulkEditOpen,setBulkEditOpen]= useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = tinhList.length > 0
    ? tinhList.map(t => t.ten_tinh)
    : [...new Set(data.map(c => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map(c => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      const params: Record<string, unknown> = { limit: 1000 }
      if (search) params.search = search
      if (mien.length)   params.mien   = mien
      if (tinh.length)   params.tinh   = tinh
      if (vendor.length) params.vendor = vendor
      setData(await cells4gApi.list(params))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getTinhList().then(setTinhList)
    getAntennaList().then((list: AntennaItem[]) => {
      const sorted = [...list].sort((a, b) => {
        const aU = a.name.toUpperCase().includes('CHƯA XÁC ĐỊNH') || a.name.toUpperCase().includes('CHUA XAC DINH')
        const bU = b.name.toUpperCase().includes('CHƯA XÁC ĐỊNH') || b.name.toUpperCase().includes('CHUA XAC DINH')
        if (aU) return -1; if (bU) return 1; return 0
      })
      setAntennaList(sorted)
    })
  }, [search, mien, tinh, vendor])

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportCells4G({ search: search || undefined, mien: mien.length ? mien : undefined, tinh: tinh.length ? tinh : undefined, vendor: vendor.length ? vendor : undefined })
      message.success(`Xuất Excel thành công (${data.length} cells)`)
    } catch (e: any) { message.error(e?.message || 'Xuất thất bại')
    } finally { setExporting(false) }
  }

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find(s => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell4G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) { await cells4gApi.update(editing.id, values); message.success('Cập nhật thành công') }
      else         { await cells4gApi.create(values);             message.success('Tạo cell thành công') }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Có lỗi xảy ra') }
  }

  const handleDelete = async (id: number) => {
    await cells4gApi.remove(id); message.success('Đã xóa')
    setSelectedIds(prev => prev.filter(x => x !== id)); load()
  }

  const handleBulkDelete = async () => {
    const result = await cells4gApi.bulkDelete(selectedIds)
    if (result.deleted) message.success(`Đã xóa ${result.deleted} cell`)
    if (result.errors.length > 0) message.warning(`${result.errors.length} lỗi`)
    setSelectedIds([]); load()
  }

  const handleBulkEdit = async (changes: Record<string, unknown>) => {
    const result = await cells4gApi.bulkUpdate(selectedIds, changes)
    if (result.updated) message.success(`Đã cập nhật ${result.updated} cell`)
    if (result.errors && result.errors.length > 0) message.warning(`${result.errors.length} lỗi`)
    setSelectedIds([]); load()
  }

  const rowSelection: TableRowSelection<Cell4G> = {
    selectedRowKeys: selectedIds,
    onChange: keys => setSelectedIds(keys as number[]),
    selections: [Table.SELECTION_ALL, Table.SELECTION_INVERT, Table.SELECTION_NONE],
  }

  const columns: ColumnsType<Cell4G> = [
    { title: 'Hành động', key: 'action', fixed: 'left', width: 90,
      render: (_: unknown, r: Cell4G) => (
        <Space size={4}>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xóa cell này?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      )},
    { title: 'Miền', dataIndex: 'mien', fixed: 'left', width: 70 },
    { title: 'Tỉnh', dataIndex: 'tinh', fixed: 'left', width: 160 },
    { title: 'Phường/Xã', dataIndex: 'phuong_xa', width: 160 },
    { title: 'Site Name Old', dataIndex: 'site_name_old', width: 200, ellipsis: { showTitle: true } },
    { title: 'Cell Name Old', dataIndex: 'cell_name_old', width: 200, ellipsis: { showTitle: true } },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 220, ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 220, ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90, render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN', dataIndex: 'moran', width: 120 },
    { title: 'Lat', dataIndex: 'lat', width: 110 },
    { title: 'Long', dataIndex: 'long', width: 110 },
    { title: 'Vùng phủ sóng', dataIndex: 'vung_phu_song', width: 120 },
    { title: 'Vendor', dataIndex: 'vendor', width: 100 },
    { title: 'Độ cao anten', dataIndex: 'do_cao_anten', width: 120 },
    { title: 'Azimuth', dataIndex: 'azimuth', width: 90 },
    { title: 'M-tilt', dataIndex: 'm_tilt', width: 80 },
    { title: 'E-Tilt', dataIndex: 'e_tilt', width: 80 },
    { title: 'Total Tilt', dataIndex: 'total_tilt', width: 100 },
    { title: 'Loại Anten', dataIndex: 'loai_anten', width: 200, ellipsis: { showTitle: true } },
    { title: 'Chung anten', dataIndex: 'chung_anten', width: 120 },
    { title: 'Baseband', dataIndex: 'baseband', width: 120 },
    { title: 'RF', dataIndex: 'rf', width: 100 },
    { title: 'EnodeB ID', dataIndex: 'enodeb_id', width: 110 },
    { title: 'Cell ID', dataIndex: 'cell_id', width: 100 },
    { title: 'EARFCN', dataIndex: 'earfcn', width: 90 },
    { title: 'TAC', dataIndex: 'tac', width: 80 },
    { title: 'PCI', dataIndex: 'pci', width: 80 },
    { title: 'Root Sequence ID', dataIndex: 'root_sequence_id', width: 150 },
    { title: 'MIMO', dataIndex: 'mimo', width: 80, render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
    { title: 'Bandwidth', dataIndex: 'bandwidth', width: 110 },
    { title: 'Cell max power (dBm)', dataIndex: 'cell_max_power', width: 165 },
    { title: 'ECI', dataIndex: 'eci', width: 120 },
    { title: 'BBUname', dataIndex: 'bbu_name', width: 130 },
    { title: 'Cell status', dataIndex: 'cell_status', width: 140 },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 4G</Typography.Title>
        <Space>
          <Tooltip title="Xuất dữ liệu hiện tại ra Excel">
            <Button icon={<DownloadOutlined />} loading={exporting} onClick={handleExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>
              Xuất Excel ({data.length})
            </Button>
          </Tooltip>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>Import Excel</Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>Thêm mới</Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tìm cell / site name..."
                 value={search} onChange={e => setSearch(e.target.value)} allowClear />
        </Col>
        <Col flex="150px">
          <Select mode="multiple" placeholder="Miền" allowClear maxTagCount={2}
                  style={{ width: '100%' }} value={mien} onChange={setMien}>
            {['MB','MT','MN'].map(m => <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="240px">
          <Select mode="multiple" placeholder="Tỉnh" allowClear showSearch maxTagCount={2}
                  style={{ width: '100%' }} value={tinh} onChange={setTinh}
                  filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map(t => <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="200px">
          <Select mode="multiple" placeholder="Vendor" allowClear maxTagCount={2}
                  style={{ width: '100%' }} value={vendor} onChange={setVendor}>
            {vendorOptions.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien([]); setTinh([]); setVendor([]) }}>Xóa lọc</Button>
        </Col>
      </Row>

      {selectedIds.length > 0 && (
        <Row style={{ marginBottom: 12 }}>
          <Col>
            <Space style={{ background: '#e6f7ff', border: '1px solid #91d5ff', borderRadius: 6, padding: '8px 16px' }}>
              <Typography.Text strong>Đã chọn {selectedIds.length} cell</Typography.Text>
              <Button type="primary" icon={<EditOutlined />} onClick={() => setBulkEditOpen(true)}>Sửa hàng loạt</Button>
              <Popconfirm title={`Xóa ${selectedIds.length} cell đã chọn?`} onConfirm={handleBulkDelete}>
                <Button danger icon={<DeleteOutlined />}>Xóa hàng loạt</Button>
              </Popconfirm>
              <Button onClick={() => setSelectedIds([])}>Bỏ chọn</Button>
            </Space>
          </Col>
        </Row>
      )}

      <Table rowSelection={rowSelection} columns={columns} dataSource={data} rowKey="id"
             loading={loading} size="small" scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: t => `${t} cells`, showSizeChanger: true }} />

      <Modal title={editing ? 'Chỉnh sửa Cell 4G' : 'Thêm Cell 4G mới'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={900} okText="Lưu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}><Form.Item name="site_id" label="Site" rules={[{ required: !editing }]}>
              <Select showSearch optionFilterProp="children" allowClear placeholder="Chọn site..."
                      onChange={handleSiteSelect} disabled={Boolean(editing)}
                      filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                {sites.map(s => <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
              </Select>
            </Form.Item></Col>
            <Col span={12}><Form.Item name="site_name_old" label="Site Name Old"><Input /></Form.Item></Col>
            <Col span={12}><Form.Item name="site_name" label="Site Name">
              <Input readOnly={!editing} style={!editing ? { background: '#f5f5f5' } : {}} />
            </Form.Item></Col>
            <Col span={12}><Form.Item name="cell_name_old" label="Cell Name Old"><Input /></Form.Item></Col>
            <Col span={12}><Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}><Input /></Form.Item></Col>
            <Col span={6}><Form.Item name="cell_vip" label="Cell VIP">
              <Select allowClear><Select.Option value="VIP">VIP</Select.Option><Select.Option value="VVIP">VVIP</Select.Option></Select>
            </Form.Item></Col>
            <Col span={6}><Form.Item name="moran" label="MORAN">
              <Select allowClear><Select.Option value="VNPT HOST">VNPT HOST</Select.Option><Select.Option value="MBF HOST">MBF HOST</Select.Option></Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="lat" label="Lat" rules={[{ validator: latValidator }]}><InputNumber style={{ width: '100%' }} precision={5} /></Form.Item></Col>
            <Col span={8}><Form.Item name="long" label="Long" rules={[{ validator: lonValidator }]}><InputNumber style={{ width: '100%' }} precision={5} /></Form.Item></Col>
            <Col span={8}><Form.Item name="vung_phu_song" label="Vùng phủ sóng">
              <Select allowClear><Select.Option value="Indoor">Indoor</Select.Option><Select.Option value="Outdoor">Outdoor</Select.Option></Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="vendor" label="Vendor">
              <Select allowClear>{['Ericsson','Nokia','Huawei','ZTE','Samsung'].map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="do_cao_anten" label="Độ cao anten (m)"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="azimuth" label="Azimuth (0–359)" rules={[{ validator: azimuthValidator }]}><InputNumber style={{ width: '100%' }} min={0} max={359} /></Form.Item></Col>
            <Col span={8}><Form.Item name="m_tilt" label="M-tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="e_tilt" label="E-Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="total_tilt" label="Total Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={24}><Form.Item name="loai_anten" label="Loại Anten">
              <Select showSearch allowClear filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                {antennaList.map(a => <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
              </Select>
            </Form.Item></Col>
            <Col span={12}><Form.Item name="chung_anten" label="Chung anten">
              <Select allowClear>{CHUNG_ANTEN_4G.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="baseband" label="Baseband"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="rf" label="RF"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="enodeb_id" label="EnodeB ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="earfcn" label="EARFCN"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="tac" label="TAC"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="pci" label="PCI"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="root_sequence_id" label="Root Sequence ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="mimo" label="MIMO">
              <Select allowClear>{['2x2','4x4','8x8'].map(m => <Select.Option key={m} value={m}>{m}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="bandwidth" label="Bandwidth (MHz)"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_max_power" label="Cell max power (dBm)"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="eci" label="ECI"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="bbu_name" label="BBUname"><Input /></Form.Item></Col>
            <Col span={16}><Form.Item name="cell_status" label="Cell status (at dump time)"><Input /></Form.Item></Col>
          </Row>
        </Form>
      </Modal>

      <CellBulkEditModal
        open={bulkEditOpen}
        onClose={() => setBulkEditOpen(false)}
        count={selectedIds.length}
        tech="4g"
        antennaList={antennaList}
        onConfirm={handleBulkEdit}
      />

      <DryRunModal open={dryRunOpen} onClose={() => setDryRunOpen(false)}
        title="Import Cell 4G từ Excel" templateKey="cell-4g"
        dryRunFn={cells4gApi.dryRunExcel} importFn={cells4gApi.importExcel} onSuccess={load} />
    </div>
  )
}
