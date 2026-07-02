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
        message.success('Cập nhật thành công')
      } else {
        await api.post('/api/v1/users/', values)
        message.success('Tạo user thành công')
      }
      setModalOpen(false)
      load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Lỗi')
    }
  }

  const handleDelete = async (id: number) => {
    await api.delete(`/api/v1/users/${id}`)
    message.success('Đã xóa user')
    load()
  }

  const columns = [
    { title: 'Username', dataIndex: 'username' },
    { title: 'Email',    dataIndex: 'email'    },
    { title: 'Họ tên',   dataIndex: 'full_name' },
    {
      title: 'Role', dataIndex: 'role',
      render: (v: string) =>
        <Tag color={v === 'admin' ? 'red' : 'blue'}>{v.toUpperCase()}</Tag>,
    },
    {
      title: 'Trang thái', dataIndex: 'is_active',
      render: (v: boolean) =>
        <Tag color={v ? 'green' : 'default'}>{v ? 'Active' : 'Inactive'}</Tag>,
    },
    {
      title: 'Provider', dataIndex: 'auth_provider',
      render: (v: string) => <Tag>{v}</Tag>,
    },
    {
      title: 'Hành động',
      render: (_: unknown, r: User) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xóa user?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quản lý người dùng</Typography.Title>
        <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
          Thêm user
        </Button>
      </Row>

      <Table columns={columns} dataSource={users} rowKey="id"
             loading={loading} size="small" pagination={{ pageSize: 20 }} />

      <Modal title={editing ? 'Chỉnh sửa user' : 'Thêm user mới'}
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
          <Form.Item name="full_name" label="Họ tên">
            <Input />
          </Form.Item>
          {!editing && (
            <Form.Item name="password" label="Mật khẩu"
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
          <Form.Item name="is_active" label="Trạng thái">
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
