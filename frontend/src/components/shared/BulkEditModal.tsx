/**
 * BulkEditModal – Generic bulk-edit modal.
 *
 * Only fields that the user explicitly fills in are sent as "changes".
 * Fields left blank/untouched are NOT included in the bulk update payload,
 * so existing values on each record are preserved.
 *
 * Usage: render the specific form fields as `children`.
 * The parent passes `onConfirm(changes)` which receives only filled fields.
 */
import React, { useState } from 'react'
import { Modal, Form, Alert, Typography, Space, Button, Divider } from 'antd'
import { EditOutlined, ExclamationCircleOutlined } from '@ant-design/icons'

interface Props {
  open:      boolean
  onClose:   () => void
  title:     string
  count:     number
  onConfirm: (changes: Record<string, unknown>) => Promise<void>
  children:  React.ReactNode
}

export default function BulkEditModal({
  open, onClose, title, count, onConfirm, children,
}: Props) {
  const [form]    = Form.useForm()
  const [busy,    setBusy]    = useState(false)
  const [errors,  setErrors]  = useState<string[]>([])

  const handleOk = async () => {
    try {
      await form.validateFields()
    } catch {
      return // validation failed – don't submit
    }
    const all = form.getFieldsValue()
    // Only include fields that were actually set (not undefined/null/"")
    const changes: Record<string, unknown> = {}
    Object.entries(all).forEach(([k, v]) => {
      if (v !== undefined && v !== null && v !== '') {
        changes[k] = v
      }
    })
    if (Object.keys(changes).length === 0) {
      setErrors(['Vui lòng điền ít nhất một trường để cập nhật'])
      return
    }
    setBusy(true)
    setErrors([])
    try {
      await onConfirm(changes)
      form.resetFields()
      onClose()
    } catch (e: any) {
      setErrors([e?.response?.data?.detail || e?.message || 'Có lỗi xảy ra'])
    } finally {
      setBusy(false)
    }
  }

  const handleClose = () => {
    form.resetFields()
    setErrors([])
    onClose()
  }

  return (
    <Modal
      title={
        <Space>
          <EditOutlined style={{ color: '#1890ff' }} />
          <span>{title}</span>
        </Space>
      }
      open={open}
      onCancel={handleClose}
      onOk={handleOk}
      okText="Cập nhật tất cả"
      cancelText="Hủy"
      confirmLoading={busy}
      width={860}
      destroyOnClose
    >
      <Alert
        type="warning"
        showIcon
        icon={<ExclamationCircleOutlined />}
        style={{ marginBottom: 16 }}
        message={
          <span>
            Đang cập nhật <strong>{count}</strong> bản ghi được chọn.{' '}
            Chỉ các trường bạn <strong>điền vào</strong> mới được cập nhật – trường để trống sẽ giữ nguyên giá trị cũ.
          </span>
        }
      />
      {errors.length > 0 && (
        <Alert
          type="error"
          showIcon
          style={{ marginBottom: 16 }}
          message="Lỗi"
          description={errors.map((e, i) => <div key={i}>{e}</div>)}
        />
      )}
      <Form form={form} layout="vertical">
        {children}
      </Form>
    </Modal>
  )
}
