import React, { useState, useEffect } from 'react'
import {
  Typography, Form, Row, Col, Select, Button,
  Table, Space, Tag, Divider,
} from 'antd'
import { SearchOutlined, DownloadOutlined, ClearOutlined } from '@ant-design/icons'
import { getReport, getVendors } from '@/api/report'
import type { ReportRow } from '@/types'

export default function ReportPage() {
  const [form]    = Form.useForm()
  const [data,    setData]    = useState<ReportRow[]>([])
  const [totals,  setTotals]  = useState<ReportRow | null>(null)
  const [loading, setLoading] = useState(false)
  const [vendors, setVendors] = useState<string[]>([])

  useEffect(() => {
    getVendors().then((rows: any[]) => {
      const v = new Set<string>()
      rows.forEach((r: any) => { if (r.vendor_4g) v.add(r.vendor_4g) })
      setVendors([...v])
    })
  }, [])

  const onSearch = async (values: Record<string, string>) => {
    setLoading(true)
    try {
      const params = Object.fromEntries(
        Object.entries(values).filter(([, v]) => v !== undefined && v !== ''),
      )
      const res = await getReport(params)
      setData(res.rows)
      setTotals(res.totals)
    } finally {
      setLoading(false)
    }
  }

  const columns = [
    { title: 'Mien',   dataIndex: 'mien',      width: 70  },
    { title: 'Tinh',   dataIndex: 'tinh',      width: 150 },
    { title: 'Site',   dataIndex: 'site_name', width: 150 },
    { title: 'Site 2G', dataIndex: 'site_2g', width: 80,
      render: (v: number) => v ? <Tag color="green">{v}</Tag>  : '-' },
    { title: 'Site 3G', dataIndex: 'site_3g', width: 80,
      render: (v: number) => v ? <Tag color="blue">{v}</Tag>   : '-' },
    { title: 'Site 4G', dataIndex: 'site_4g', width: 80,
      render: (v: number) => v ? <Tag color="orange">{v}</Tag> : '-' },
    { title: 'Site 5G', dataIndex: 'site_5g', width: 80,
      render: (v: number) => v ? <Tag color="red">{v}</Tag>    : '-' },
    { title: 'Cell 3G', dataIndex: 'cell_3g', width: 80 },
    { title: 'Cell 4G', dataIndex: 'cell_4g', width: 80 },
    { title: 'Cell 5G', dataIndex: 'cell_5g', width: 80 },
  ]

  return (
    <div>
      <Typography.Title level={3}>Bao cao tong hop</Typography.Title>

      <Form form={form} layout="vertical" onFinish={onSearch}>
        <Row gutter={16}>
          <Col span={4}>
            <Form.Item name="mien" label="Mien">
              <Select allowClear placeholder="Tat ca">
                {['MB','MT','MN'].map((m) =>
                  <Select.Option key={m} value={m}>{m}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={4}>
            <Form.Item name="vendor" label="Vendor">
              <Select allowClear placeholder="Tat ca">
                {vendors.map((v) =>
                  <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={4}>
            <Form.Item name="mimo" label="MIMO">
              <Select allowClear placeholder="Tat ca">
                {['2x2','4x4','8x8'].map((m) =>
                  <Select.Option key={m} value={m}>{m}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={4}>
            <Form.Item name="vung_phu_song" label="Vung phu song">
              <Select allowClear placeholder="Tat ca">
                <Select.Option value="Indoor">Indoor</Select.Option>
                <Select.Option value="Outdoor">Outdoor</Select.Option>
              </Select>
            </Form.Item>
          </Col>
          <Col span={8} style={{ display:'flex', alignItems:'flex-end', paddingBottom:24 }}>
            <Space>
              <Button type="primary" icon={<SearchOutlined />}
                      htmlType="submit" loading={loading}>
                Tim kiem
              </Button>
              <Button icon={<ClearOutlined />} onClick={() => {
                form.resetFields(); setData([]); setTotals(null)
              }}>
                Xoa loc
              </Button>
              <Button
                icon={<DownloadOutlined />}
                onClick={() => {
                  const token = localStorage.getItem('sl_token') || ''
                  const params = new URLSearchParams()
                  if (token) params.append('token', token)
                  // add current filters
                  const vals = form.getFieldsValue()
                  if (vals.mien)          params.append('mien', vals.mien)
                  if (vals.vendor)        params.append('vendor', vals.vendor)
                  if (vals.mimo)          params.append('mimo', vals.mimo)
                  if (vals.vung_phu_song) params.append('vung_phu_song', vals.vung_phu_song)
                  window.open(`/api/v1/report/export-csv?${params.toString()}`, '_blank')
                }}
              >
                Xuat CSV
              </Button>
            </Space>
          </Col>
        </Row>
      </Form>

      <Divider />

      {totals && (
        <Row gutter={8} style={{ marginBottom: 16 }}>
          {[
            { label:'Tong Site 2G', val:totals.site_2g, color:'#95de64' },
            { label:'Tong Site 3G', val:totals.site_3g, color:'#69b1ff' },
            { label:'Tong Site 4G', val:totals.site_4g, color:'#ffd666' },
            { label:'Tong Site 5G', val:totals.site_5g, color:'#ff7875' },
            { label:'Tong Cell 3G', val:totals.cell_3g, color:'#69b1ff' },
            { label:'Tong Cell 4G', val:totals.cell_4g, color:'#ffd666' },
            { label:'Tong Cell 5G', val:totals.cell_5g, color:'#ff7875' },
          ].map((t) => (
            <Col key={t.label}>
              <Tag color={t.color} style={{ fontSize:14, padding:'4px 12px' }}>
                {t.label}: <strong>{t.val}</strong>
              </Tag>
            </Col>
          ))}
        </Row>
      )}

      <Table
        columns={columns}
        dataSource={data}
        rowKey={(_, i) => String(i)}
        loading={loading}
        size="small"
        scroll={{ x: 900 }}
        pagination={{ pageSize: 50, showTotal: (t) => `${t} records` }}
      />
    </div>
  )
}
