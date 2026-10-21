import React, { useState } from 'react'
import { Alert, Col, Form, Input, Modal, Row, Select, message } from 'antd'
import type { UploadFile } from 'antd/es/upload/interface'
import { useLocation } from 'react-router-dom'
import {
  createTicket, uploadAttachments, notifyFeedbackChanged, errText, FbDetail,
} from '@/api/feedback'
import { categoryOptions, priorityOptions } from './meta'
import { AttachmentPicker, MAX_FILES, filesFromPaste, toRawFiles } from './AttachmentPicker'

interface Props {
  open: boolean
  onClose: () => void
  onCreated?: (t: FbDetail) => void
}

export default function FeedbackFormModal({ open, onClose, onCreated }: Props) {
  const [form] = Form.useForm()
  const [files, setFiles] = useState<UploadFile[]>([])
  const [busy, setBusy] = useState(false)
  const loc = useLocation()

  const reset = () => { form.resetFields(); setFiles([]) }
  const cancel = () => { reset(); onClose() }

  const submit = async () => {
    let v: Record<string, unknown>
    try { v = await form.validateFields() } catch { return }
    setBusy(true)
    try {
      const t = await createTicket({
        ...v,
        page_url: (loc.pathname + loc.search).slice(0, 480),
        user_agent: navigator.userAgent.slice(0, 480),
      })
      const raw = toRawFiles(files)
      if (raw.length) {
        try { await uploadAttachments(t.id, raw) }
        catch { message.warning('Yêu cầu đã được tạo nhưng tải tệp đính kèm thất bại – bạn có thể đính kèm lại trong trang chi tiết') }
      }
      notifyFeedbackChanged()
      reset()
      onClose()
      onCreated?.(t)
    } catch (e: any) {
      message.error(errText(e, 'Gửi yêu cầu thất bại'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title="📝 Gửi yêu cầu hỗ trợ / góp ý"
      open={open} onCancel={cancel} onOk={submit}
      okText="Gửi yêu cầu" cancelText="Hủy" confirmLoading={busy} width={720}
    >
      <Alert type="info" showIcon style={{ marginBottom: 12 }}
        message="Mô tả càng cụ thể (site/cell nào, thao tác nào, báo lỗi gì), chúng tôi xử lý càng nhanh. Trang bạn đang xem sẽ được đính kèm tự động." />
      <Form form={form} layout="vertical" initialValues={{ category: 'help', priority: 'normal' }}>
        <Row gutter={12}>
          <Col span={12}>
            <Form.Item name="category" label="Loại yêu cầu" rules={[{ required: true }]}>
              <Select options={categoryOptions} />
            </Form.Item>
          </Col>
          <Col span={12}>
            <Form.Item name="priority" label="Mức độ khẩn cấp" rules={[{ required: true }]}>
              <Select options={priorityOptions} />
            </Form.Item>
          </Col>
        </Row>
        <Form.Item name="title" label="Tiêu đề"
          rules={[{ required: true, message: 'Nhập tiêu đề' }, { min: 3, message: 'Tối thiểu 3 ký tự' }]}>
          <Input maxLength={255} placeholder="Tóm tắt ngắn gọn vấn đề / yêu cầu" />
        </Form.Item>
        <Form.Item name="description" label="Nội dung chi tiết"
          rules={[{ required: true, message: 'Nhập nội dung' }, { min: 5, message: 'Tối thiểu 5 ký tự' }]}>
          <Input.TextArea rows={6} placeholder="Mô tả các bước thực hiện, kết quả mong muốn, kết quả thực tế..."
            onPaste={(e) => {
              const add = filesFromPaste(e)
              if (add.length) setFiles((p) => [...p, ...add].slice(0, MAX_FILES))
            }} />
        </Form.Item>
        <Form.Item name="related_ref" label="Site / Cell liên quan (không bắt buộc)">
          <Input maxLength={255} placeholder="vd: HNI001 hoặc HNI001_3G_A" />
        </Form.Item>
        <AttachmentPicker files={files} onChange={setFiles} />
      </Form>
    </Modal>
  )
}
