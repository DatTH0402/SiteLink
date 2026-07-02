import React, { useEffect, useState } from 'react'
import { Row, Col, Card, Statistic, Typography, Spin } from 'antd'
import {
  DatabaseOutlined, PartitionOutlined,
  WifiOutlined, RiseOutlined,
} from '@ant-design/icons'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer,
} from 'recharts'
import api from '@/api/client'
import { getReportByProvince, getReportCellsByProvince } from '@/api/report'
import type { ProvinceChartItem, CellProvinceChartItem } from '@/types'

const truncate = (s: string, n = 10) =>
  s.length > n ? s.slice(0, n) + '\u2026' : s

interface ProvinceBar { tinh: string; value: number }

function ProvinceBarChart({
  title, data, color, valueKey,
}: {
  title: string
  data: ProvinceBar[]
  color: string
  valueKey: string
}) {
  if (!data.length) {
    return (
      <Card title={title} style={{ height: 320 }}>
        <div style={{
          display: 'flex', alignItems: 'center',
          justifyContent: 'center', height: 240,
        }}>
          <Typography.Text type="secondary">Chua co du lieu</Typography.Text>
        </div>
      </Card>
    )
  }
  return (
    <Card title={title} style={{ height: 340 }}>
      <ResponsiveContainer width="100%" height={260}>
        <BarChart data={data} margin={{ top: 4, right: 16, left: 0, bottom: 60 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis
            dataKey="tinh"
            tickFormatter={(v) => truncate(v, 10)}
            angle={-40}
            textAnchor="end"
            interval={0}
            tick={{ fontSize: 11 }}
          />
          <YAxis allowDecimals={false} tick={{ fontSize: 11 }} />
          <Tooltip
            formatter={(val) => [val, valueKey]}
            labelFormatter={(l) => `Tinh: ${l}`}
          />
          <Bar dataKey="value" fill={color} radius={[3, 3, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </Card>
  )
}

export default function DashboardPage() {
  const [counts, setCounts] = useState({ sites: 0, c3g: 0, c4g: 0, c5g: 0 })
  const [loadingCounts,  setLoadingCounts]  = useState(true)
  const [siteByProv,     setSiteByProv]     = useState<ProvinceBar[]>([])
  const [cell3gProv,     setCell3gProv]     = useState<ProvinceBar[]>([])
  const [cell4gProv,     setCell4gProv]     = useState<ProvinceBar[]>([])
  const [cell5gProv,     setCell5gProv]     = useState<ProvinceBar[]>([])
  const [loadingCharts,  setLoadingCharts]  = useState(true)

  useEffect(() => {
    Promise.all([
      api.get('/api/v1/sites/count'),
      api.get('/api/v1/cells-3g/count'),
      api.get('/api/v1/cells-4g/count'),
      api.get('/api/v1/cells-5g/count'),
    ])
      .then(([s, c3, c4, c5]) => {
        setCounts({
          sites: s.data.count,
          c3g:   c3.data.count,
          c4g:   c4.data.count,
          c5g:   c5.data.count,
        })
      })
      .finally(() => setLoadingCounts(false))

    Promise.all([
      getReportByProvince(),
      getReportCellsByProvince('3g'),
      getReportCellsByProvince('4g'),
      getReportCellsByProvince('5g'),
    ])
      .then(([sites, c3g, c4g, c5g]) => {
        setSiteByProv(
          (sites as ProvinceChartItem[]).map((r) => ({
            tinh: r.tinh, value: r.site_count,
          })),
        )
        setCell3gProv(
          (c3g as CellProvinceChartItem[]).map((r) => ({
            tinh: r.tinh, value: r.cell_count,
          })),
        )
        setCell4gProv(
          (c4g as CellProvinceChartItem[]).map((r) => ({
            tinh: r.tinh, value: r.cell_count,
          })),
        )
        setCell5gProv(
          (c5g as CellProvinceChartItem[]).map((r) => ({
            tinh: r.tinh, value: r.cell_count,
          })),
        )
      })
      .finally(() => setLoadingCharts(false))
  }, [])

  const stats = [
    { title: 'Tổng số Site', value: counts.sites, icon: <DatabaseOutlined />,  color: '#1890ff' },
    { title: 'Cell 3G',      value: counts.c3g,   icon: <PartitionOutlined />, color: '#52c41a' },
    { title: 'Cell 4G',      value: counts.c4g,   icon: <WifiOutlined />,      color: '#faad14' },
    { title: 'Cell 5G',      value: counts.c5g,   icon: <RiseOutlined />,      color: '#f5222d' },
  ]

  return (
    <div>
      <Typography.Title level={3}>Dashboard</Typography.Title>

      <Row gutter={[16, 16]}>
        {stats.map((s) => (
          <Col xs={24} sm={12} lg={6} key={s.title}>
            <Card>
              <Statistic
                title={s.title}
                value={s.value}
                prefix={React.cloneElement(
                  s.icon as React.ReactElement,
                  { style: { color: s.color } },
                )}
                valueStyle={{ color: s.color }}
                loading={loadingCounts}
              />
            </Card>
          </Col>
        ))}
      </Row>

      <div style={{ marginTop: 24 }}>
        {loadingCharts ? (
          <div style={{ textAlign: 'center', padding: 48 }}>
            <Spin size="large" />
          </div>
        ) : (
          <>
            <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
              <Col xs={24}>
                <ProvinceBarChart
                  title="Số lượng Site theo tỉnh / Thành phố"
                  data={siteByProv}
                  color="#1890ff"
                  valueKey="So Site"
                />
              </Col>
            </Row>
            <Row gutter={[16, 16]}>
              <Col xs={24} lg={8}>
                <ProvinceBarChart
                  title="Số lượng Cell 3G theo tỉnh"
                  data={cell3gProv}
                  color="#52c41a"
                  valueKey="Cell 3G"
                />
              </Col>
              <Col xs={24} lg={8}>
                <ProvinceBarChart
                  title="Số lượng Cell 4G theo tỉnh"
                  data={cell4gProv}
                  color="#faad14"
                  valueKey="Cell 4G"
                />
              </Col>
              <Col xs={24} lg={8}>
                <ProvinceBarChart
                  title="Số lượng Cell 5G theo tỉnh"
                  data={cell5gProv}
                  color="#f5222d"
                  valueKey="Cell 5G"
                />
              </Col>
            </Row>
          </>
        )}
      </div>
    </div>
  )
}
