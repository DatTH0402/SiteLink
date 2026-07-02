import React, { useEffect, useState } from 'react'
import {
  Typography, Table, Select, Space, Tag, Row,
  Button, Input, Tooltip,
} from 'antd'
import { ReloadOutlined, SearchOutlined } from '@ant-design/icons'
import { getAuditLogs } from '@/api/report'
import type { AuditLog } from '@/types'

const ACTION_COLOR: Record<string, string> = {
  CREATE: 'green',
  UPDATE: 'blue',
  DELETE: 'red',
  IMPORT: 'purple',
}

const TABLE_OPTIONS = [
  'sites', 'cells_3g', 'cells_4g', 'cells_5g', 'antennas', 'users',
]

export default function AuditPage() {
  const [logs,    setLogs]    = useState<AuditLog[]>([])
  const [loading, setLoading] = useState(false)
  const [action,  setAction]  = useState<string | undefined>()
  const [table,   setTable]   = useState<string | undefined>()
  const [search,  setSearch]  = useState('')

  const load = () => {
    setLoading(true)
    getAuditLogs({ action, table_name: table, limit: 500 })
      .then((data: AuditLog[]) => {
        if (search) {
          const q = search.toLowerCase()
          setLogs(
            data.filter(
              (l) =>
                l.username?.toLowerCase().includes(q) ||
                l.full_name?.toLowerCase().includes(q) ||
                l.email?.toLowerCase().includes(q),
            ),
          )
        } else {
          setLogs(data)
        }
      })
      .finally(() => setLoading(false))
  }

  useEffect(() => { load() }, [action, table, search])

  const columns = [
    {
      title: 'Thoi gian',
      dataIndex: 'timestamp',
      width: 160,
      sorter: (a: AuditLog, b: AuditLog) =>
        new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime(),
      defaultSortOrder: 'descend' as const,
      render: (v: string) =>
        v ? new Date(v).toLocaleString('vi-VN') : '-',
    },
    {
      title: 'Username',
      dataIndex: 'username',
      width: 140,
      render: (v: string) => <strong>{v}</strong>,
    },
    {
      title: 'Ho ten',
      dataIndex: 'full_name',
      width: 160,
      ellipsis: { showTitle: true },
      render: (v: string) => v || <span style={{ color: '#ccc' }}>-</span>,
    },
    {
      title: 'Email',
      dataIndex: 'email',
      width: 200,
      ellipsis: { showTitle: true },
      render: (v: string) =>
        v ? (
          <Tooltip title={v}>
            <span style={{ fontSize: 12, color: '#666' }}>{v}</span>
          </Tooltip>
        ) : (
          <span style={{ color: '#ccc' }}>-</span>
        ),
    },
    {
      title: 'Action',
      dataIndex: 'action',
      width: 90,
      render: (v: string) => (
        <Tag color={ACTION_COLOR[v] || 'default'}>{v}</Tag>
      ),
    },
    {
      title: 'Bang',
      dataIndex: 'table_name',
      width: 120,
      render: (v: string) => <code style={{ fontSize: 11 }}>{v}</code>,
    },
    {
      title: 'Record ID',
      dataIndex: 'record_id',
      width: 90,
    },
    {
      title: 'Du lieu cu',
      dataIndex: 'old_value',
      ellipsis: true,
      render: (v: string) =>
        v ? (
          <Tooltip title={v} overlayStyle={{ maxWidth: 400 }}>
            <span
              style={{
                fontFamily: 'monospace',
                fontSize: 11,
                color: '#cf1322',
              }}
            >
              {v.slice(0, 80)}{v.length > 80 ? '…' : ''}
            </span>
          </Tooltip>
        ) : '-',
    },
    {
      title: 'Du lieu moi',
      dataIndex: 'new_value',
      ellipsis: true,
      render: (v: string) =>
        v ? (
          <Tooltip title={v} overlayStyle={{ maxWidth: 400 }}>
            <span
              style={{
                fontFamily: 'monospace',
                fontSize: 11,
                color: '#237804',
              }}
            >
              {v.slice(0, 80)}{v.length > 80 ? '…' : ''}
            </span>
          </Tooltip>
        ) : '-',
    },
  ]

  return (
    <div>
      <Row
        align="middle"
        justify="space-between"
        style={{ marginBottom: 16 }}
      >
        <Typography.Title level={3} style={{ margin: 0 }}>
          Audit Log
        </Typography.Title>
        <Button icon={<ReloadOutlined />} onClick={load} loading={loading}>
          Lam moi
        </Button>
      </Row>

      <Space style={{ marginBottom: 12 }} wrap>
        <Input
          prefix={<SearchOutlined />}
          placeholder="Tim username / ho ten / email..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          allowClear
          style={{ width: 260 }}
        />
        <Select
          placeholder="Action"
          allowClear
          style={{ width: 120 }}
          onChange={setAction}
          value={action}
        >
          {['CREATE', 'UPDATE', 'DELETE', 'IMPORT'].map((a) => (
            <Select.Option key={a} value={a}>{a}</Select.Option>
          ))}
        </Select>
        <Select
          placeholder="Bang du lieu"
          allowClear
          style={{ width: 160 }}
          onChange={setTable}
          value={table}
        >
          {TABLE_OPTIONS.map((t) => (
            <Select.Option key={t} value={t}>{t}</Select.Option>
          ))}
        </Select>
        {(action || table || search) && (
          <Button
            onClick={() => {
              setAction(undefined)
              setTable(undefined)
              setSearch('')
            }}
          >
            Xoa loc
          </Button>
        )}
      </Space>

      <Typography.Text
        type="secondary"
        style={{ display: 'block', marginBottom: 8, fontSize: 12 }}
      >
        Hien thi {logs.length} ban ghi
      </Typography.Text>

      <Table
        columns={columns}
        dataSource={logs}
        rowKey="id"
        loading={loading}
        size="small"
        scroll={{ x: 1400, y: 600 }}
        bordered
        pagination={{
          pageSize: 50,
          showTotal: (t) => `${t} records`,
          showSizeChanger: true,
        }}
      />
    </div>
  )
}
