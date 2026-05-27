import React, { useEffect, useState } from 'react'
import { Row, Col, Card, Statistic, Typography } from 'antd'
import {
  DatabaseOutlined, PartitionOutlined,
  WifiOutlined, RiseOutlined,
} from '@ant-design/icons'
import api from '@/api/client'

export default function DashboardPage() {
  const [counts, setCounts] = useState({ sites: 0, c3g: 0, c4g: 0, c5g: 0 })

  useEffect(() => {
    Promise.all([
      api.get('/api/v1/sites/count'),
      api.get('/api/v1/cells-3g/count'),
      api.get('/api/v1/cells-4g/count'),
      api.get('/api/v1/cells-5g/count'),
    ]).then(([s, c3, c4, c5]) => {
      setCounts({
        sites: s.data.count,
        c3g:   c3.data.count,
        c4g:   c4.data.count,
        c5g:   c5.data.count,
      })
    })
  }, [])

  const stats = [
    { title: 'Tong so Site', value: counts.sites, icon: <DatabaseOutlined />,  color: '#1890ff' },
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
              />
            </Card>
          </Col>
        ))}
      </Row>
    </div>
  )
}
