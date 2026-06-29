import React, { useState, useEffect } from 'react'
import {
  Typography, Form, Row, Col, Select, Button,
  Table, Space, Tag, Divider,
} from 'antd'
import { SearchOutlined, DownloadOutlined, ClearOutlined } from '@ant-design/icons'
import { getReport, getVendors, getTinhList } from '@/api/report'
import type { ReportRow, TinhItem } from '@/types'

export default function ReportPage() {
  const [form]     = Form.useForm()
  const [data,     setData]     = useState<ReportRow[]>([])
  const [totals,   setTotals]   = useState<ReportRow | null>(null)
  const [loading,  setLoading]  = useState(false)
  const [vendors,  setVendors]  = useState<string[]>([])
  const [tinhList, setTinhList] = useState<TinhItem[]>([])

  useEffect(() => {
    getVendors().then((rows: any[]) => {
      const v = new Set<string>()
      rows.forEach((r: any) => { if (r.vendor_4g) v.add(r.vendor_4g) })
      setVendors([...v])
    })
    getTinhList().then(setTinhList)
    fetchReport({})
  }, [])

  const fetchReport = async (params: Record<string, string>) => {
    setLoading(true)
    try {
      const filtered = Object.fromEntries(
        Object.entries(params).filter(([, v]) => v !== undefined && v !== ''),
      )
      const res = await getReport(filtered)
      setData(res.rows)
      setTotals(res.totals)
    } finally {
      setLoading(false)
    }
  }

  const onSearch = (values: Record<string, string>) => fetchReport(values)

  const columns = [
    { title: 'Mien',    dataIndex: 'mien',       width: 70  },
    { title: 'Tinh',    dataIndex: 'tinh',        width: 180 },
    {
      title: 'So Site', dataIndex: 'site_count',  width: 100,
      render: (v: number) => <strong>{v}</strong>,
    },
    { title: 'Site 2G', dataIndex: 'site_2g', width: 90,
      render: (v: number) => v ? <Tag color="green">{v}</Tag>  : '-' },
    { title: 'Site 3G', dataIndex: 'site_3g', width: 90,
      render: (v: number) => v ? <Tag color="blue">{v}</Tag>   : '-' },
    { title: 'Site 4G', dataIndex: 'site_4g', width: 90,
      render: (v: number) => v ? <Tag color="orange">{v}</Tag> : '-' },
    { title: 'Site 5G', dataIndex: 'site_5g', width: 90,
      render: (v: number) => v ? <Tag color="red">{v}</Tag>    : '-' },
    { title: 'Cell 3G', dataIndex: 'cell_3g', width: 90 },
    { title: 'Cell 4G', dataIndex: 'cell_4g', width: 90 },
    { title: 'Cell 5G', dataIndex: 'cell_5g', width: 90 },
  ]

  return (
    <div>
      <Typography.Title level={3}>Bao cao tong hop</Typography.Title>

      <Form form={form} layout="vertical" onFinish={onSearch}>
        <Row gutter={16}>
          <Col span={4}>
            <Form.Item name="mien" label="Mien">
              <Select allowClear placeholder="Tat ca">
                {['MB', 'MT', 'MN'].map((m) => (
                  <Select.Option key={m} value={m}>{m}</Select.Option>
                ))}
              </Select>
            </Form.Item>
          </Col>
          <Col span={5}>
            <Form.Item name="tinh" label="Tinh / Thanh pho">
              <Select
                allowClear showSearch placeholder="Tat ca"
                filterOption={(input, opt) =>
                  String(opt?.children ?? '').toLowerCase()
                    .includes(input.toLowerCase())
                }
              >
                {tinhList.map((t) => (
                  <Select.Option key={t.ten_tinh} value={t.ten_tinh}>
                    {t.ten_tinh}
                  </Select.Option>
                ))}
              </Select>
            </Form.Item>
          </Col>
          <Col span={4}>
            <Form.Item name="vendor" label="Vendor">
              <Select allowClear placeholder="Tat ca">
                {vendors.map((v) => (
                  <Select.Option key={v} value={v}>{v}</Select.Option>
                ))}
              </Select>
            </Form.Item>
          </Col>
          <Col span={4}>
            <Form.Item name="mimo" label="MIMO">
              <Select allowClear placeholder="Tat ca">
                {['2x2', '4x4', '8x8'].map((m) => (
                  <Select.Option key={m} value={m}>{m}</Select.Option>
                ))}
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
          <Col span={3} style={{ display: 'flex', alignItems: 'flex-end', paddingBottom: 24 }}>
            <Space>
              <Button type="primary" icon={<SearchOutlined />}
                      htmlType="submit" loading={loading}>
                Tim kiem
              </Button>
              <Button icon={<ClearOutlined />} onClick={() => {
                form.resetFields()
                fetchReport({})
              }}>
                Xoa loc
              </Button>
            </Space>
          </Col>
          <Col span={24} style={{ display: 'flex', justifyContent: 'flex-end', paddingBottom: 8 }}>
            <Button
              icon={<DownloadOutlined />}
              onClick={() => {
                const token = localStorage.getItem('sl_token') || ''
                const params = new URLSearchParams()
                if (token) params.append('token', token)
                const vals = form.getFieldsValue()
                if (vals.mien)          params.append('mien',          vals.mien)
                if (vals.tinh)          params.append('tinh',          vals.tinh)
                if (vals.vendor)        params.append('vendor',        vals.vendor)
                if (vals.mimo)          params.append('mimo',          vals.mimo)
                if (vals.vung_phu_song) params.append('vung_phu_song', vals.vung_phu_song)
                window.open(`/api/v1/report/export-csv?${params.toString()}`, '_blank')
              }}
            >
              Xuat CSV
            </Button>
          </Col>
        </Row>
      </Form>

      <Divider />

      {totals && (
        <Row gutter={8} style={{ marginBottom: 16 }}>
          {[
            { label: 'Tong Site',    val: totals.site_count, color: '#597ef7' },
            { label: 'Tong Site 2G', val: totals.site_2g,    color: '#95de64' },
            { label: 'Tong Site 3G', val: totals.site_3g,    color: '#69b1ff' },
            { label: 'Tong Site 4G', val: totals.site_4g,    color: '#ffd666' },
            { label: 'Tong Site 5G', val: totals.site_5g,    color: '#ff7875' },
            { label: 'Tong Cell 3G', val: totals.cell_3g,    color: '#69b1ff' },
            { label: 'Tong Cell 4G', val: totals.cell_4g,    color: '#ffd666' },
            { label: 'Tong Cell 5G', val: totals.cell_5g,    color: '#ff7875' },
          ].map((t) => (
            <Col key={t.label}>
              <Tag color={t.color} style={{ fontSize: 13, padding: '4px 10px' }}>
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
        pagination={{ pageSize: 50, showTotal: (t) => `${t} tinh / thanh pho` }}
        summary={() =>
          totals ? (
            <Table.Summary.Row style={{ background: '#fafafa', fontWeight: 700 }}>
              <Table.Summary.Cell index={0}>TONG</Table.Summary.Cell>
              <Table.Summary.Cell index={1}></Table.Summary.Cell>
              <Table.Summary.Cell index={2}>{totals.site_count}</Table.Summary.Cell>
              <Table.Summary.Cell index={3}>{totals.site_2g}</Table.Summary.Cell>
              <Table.Summary.Cell index={4}>{totals.site_3g}</Table.Summary.Cell>
              <Table.Summary.Cell index={5}>{totals.site_4g}</Table.Summary.Cell>
              <Table.Summary.Cell index={6}>{totals.site_5g}</Table.Summary.Cell>
              <Table.Summary.Cell index={7}>{totals.cell_3g}</Table.Summary.Cell>
              <Table.Summary.Cell index={8}>{totals.cell_4g}</Table.Summary.Cell>
              <Table.Summary.Cell index={9}>{totals.cell_5g}</Table.Summary.Cell>
            </Table.Summary.Row>
          ) : null
        }
      />
    </div>
  )
}
