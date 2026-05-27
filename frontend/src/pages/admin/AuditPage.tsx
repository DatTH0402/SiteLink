import React, { useEffect, useState } from 'react'
import { Typography, Table, Select, Space, Tag, Row, Button } from 'antd'
import { ReloadOutlined } from '@ant-design/icons'
import { getAuditLogs } from '@/api/report'
import type { AuditLog } from '@/types'

const ACTION_COLOR: Record<string, string> = {
  CREATE: 'green', UPDATE: 'blue', DELETE: 'red',
}

export default function AuditPage() {
  const [logs,    setLogs]    = useState<AuditLog[]>([])
  const [loading, setLoading] = useState(false)
  const [action,  setAction]  = useState<string | undefined>()
  const [table,   setTable]   = useState<string | undefined>()

  const load = () => {
    setLoading(true)
    getAuditLogs({ action, table_name: table, limit: 200 })
      .then(setLogs)
      .finally(() => setLoading(false))
  }
  useEffect(load, [action, table])

  const columns = [
    {
      title: 'Thoi gian', dataIndex: 'timestamp', width: 180,
      render: (v: string) => new Date(v).toLocaleString('vi-VN'),
    },
    { title: 'User',      dataIndex: 'username',   width: 120 },
    {
      title: 'Action', dataIndex: 'action', width: 90,
      render: (v: string) =>
        <Tag color={ACTION_COLOR[v] || 'default'}>{v}</Tag>,
    },
    { title: 'Bang',      dataIndex: 'table_name', width: 120 },
    { title: 'Record ID', dataIndex: 'record_id',  width: 90  },
    { title: 'Du lieu cu', dataIndex: 'old_value', ellipsis: true },
    { title: 'Du lieu moi', dataIndex: 'new_value', ellipsis: true },
  ]

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Audit Log</Typography.Title>
        <Button icon={<ReloadOutlined />} onClick={load}>Lam moi</Button>
      </Row>

      <Space style={{ marginBottom: 12 }}>
        <Select placeholder="Action" allowClear style={{ width: 120 }}
                onChange={setAction}>
          {['CREATE','UPDATE','DELETE'].map((a) =>
            <Select.Option key={a} value={a}>{a}</Select.Option>)}
        </Select>
        <Select placeholder="Bang du lieu" allowClear style={{ width: 160 }}
                onChange={setTable}>
          {['sites','cells_3g','cells_4g','cells_5g'].map((t) =>
            <Select.Option key={t} value={t}>{t}</Select.Option>)}
        </Select>
      </Space>

      <Table columns={columns} dataSource={logs} rowKey="id"
             loading={loading} size="small"
             pagination={{ pageSize: 50, showTotal: (t) => `${t} records` }} />
    </div>
  )
}
