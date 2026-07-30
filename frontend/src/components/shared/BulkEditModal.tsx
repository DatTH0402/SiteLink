/**
 * BulkEditModal – Generic bulk-edit modal.
 *
 * Only fields the user explicitly fills are sent as "changes".
 * Fields left blank/untouched are excluded from the payload.
 *
 * Boolean fields: pass their names in `booleanFields[]`.
 * Use a Select with value="true" / value="false" (strings) for those fields.
 * BulkEditModal converts them to real JS booleans before calling onConfirm.
 * This avoids the Switch/false-default problem where untouched Switch fields
 * always emit `false` and overwrite existing DB values.
 */
import React, { useState } from 'react'
import { Modal, Form, Alert, Space, Button } from 'antd'
import { EditOutlined, ExclamationCircleOutlined } from '@ant-design/icons'

interface Props {
  open:           boolean
  onClose:        () => void
  title:          string
  count:          number
  onConfirm:      (changes: Record<string, unknown>) => Promise<void>
  children:       React.ReactNode
  /** Names of fields whose Select values "true"/"false" should be cast to boolean */
  booleanFields?: string[]
}

export default function BulkEditModal({
  open, onClose, title, count, onConfirm, children, booleanFields = [],
}: Props) {
  const [form]   = Form.useForm()
  const [busy,   setBusy]   = useState(false)
  const [errors, setErrors] = useState<string[]>([])

  const handleOk = async () => {
    try { await form.validateFields() } catch { return }

    const all = form.getFieldsValue()
    const changes: Record<string, unknown> = {}

    Object.entries(all).forEach(([k, v]) => {
      // Skip empty / unset values
      if (v === undefined || v === null || v === '') return

      // Cast boolean Select strings → real booleans
      if (booleanFields.includes(k)) {
        if (v === 'true')  { changes[k] = true;  return }
        if (v === 'false') { changes[k] = false; return }
        // Any other value (shouldn't happen with BoolSelect) → skip
        return
      }

      changes[k] = v
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
      title={<Space><EditOutlined style={{ color: '#1890ff' }} /><span>{title}</span></Space>}
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
            Chỉ các trường bạn <strong>điền vào</strong> mới được cập nhật –
            trường để trống sẽ giữ nguyên giá trị cũ.
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
