import React, { useEffect, useState } from 'react'
import {
  Typography, Table, Button, Space, Tag, Modal,
  Form, Input, Select, Popconfirm, message, Row,
} from 'antd'
import { PlusOutlined, EditOutlined, DeleteOutlined } from '@ant-design/icons'
import api from '@/api/client'
import type { User } from '@/types'

export default function UsersPage() {
  const [users,   setUsers]   = useState<User[]>([])
  const [loading, setLoading] = useState(false)
  const [modalOpen, setModalOpen] = useState(false)
  const [editing,   setEditing]   = useState<User | null>(null)
  const [form] = Form.useForm()

  const load = () => {
    setLoading(true)
    api.get('/api/v1/users/')
       .then((r) => setUsers(r.data))
       .finally(() => setLoading(false))
  }
  useEffect(load, [])

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (u: User) => { setEditing(u); form.setFieldsValue(u); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await api.put(`/api/v1/users/${editing.id}`, values)
        message.success('Cap nhat thanh cong')
      } else {
        await api.post('/api/v1/users/', values)
        message.success('Tao user thanh cong')
      }
      setModalOpen(false)
      load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Loi')
    }
  }

  const handleDelete = async (id: number) => {
    await api.delete(`/api/v1/users/${id}`)
    message.success('Da xoa')
    load()
  }

  const columns = [
    { title: 'Username', dataIndex: 'username' },
    { title: 'Email',    dataIndex: 'email'    },
    { title: 'Ho ten',   dataIndex: 'full_name' },
    {
      title: 'Role', dataIndex: 'role',
      render: (v: string) =>
        <Tag color={v === 'admin' ? 'red' : 'blue'}>{v.toUpperCase()}</Tag>,
    },
    {
      title: 'Trang thai', dataIndex: 'is_active',
      render: (v: boolean) =>
        <Tag color={v ? 'green' : 'default'}>{v ? 'Active' : 'Inactive'}</Tag>,
    },
    {
      title: 'Provider', dataIndex: 'auth_provider',
      render: (v: string) => <Tag>{v}</Tag>,
    },
    {
      title: 'Hanh dong',
      render: (_: unknown, r: User) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa user?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quan ly nguoi dung</Typography.Title>
        <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
          Them user
        </Button>
      </Row>

      <Table columns={columns} dataSource={users} rowKey="id"
             loading={loading} size="small" pagination={{ pageSize: 20 }} />

      <Modal title={editing ? 'Chinh sua user' : 'Them user moi'}
             open={modalOpen} onOk={handleSave}
             onCancel={() => setModalOpen(false)}>
        <Form form={form} layout="vertical">
          <Form.Item name="username" label="Username"
                     rules={[{ required: !editing }]}>
            <Input disabled={Boolean(editing)} />
          </Form.Item>
          <Form.Item name="email" label="Email"
                     rules={[{ required: !editing, type: 'email' }]}>
            <Input />
          </Form.Item>
          <Form.Item name="full_name" label="Ho ten">
            <Input />
          </Form.Item>
          {!editing && (
            <Form.Item name="password" label="Mat khau"
                       rules={[{ required: true }]}>
              <Input.Password />
            </Form.Item>
          )}
          <Form.Item name="role" label="Role">
            <Select>
              <Select.Option value="user">User</Select.Option>
              <Select.Option value="admin">Admin</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="is_active" label="Trang thai">
            <Select>
              <Select.Option value={true}>Active</Select.Option>
              <Select.Option value={false}>Inactive</Select.Option>
            </Select>
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}
