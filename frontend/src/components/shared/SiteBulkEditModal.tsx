/**
 * SiteBulkEditModal
 * -----------------
 * Bulk-edit modal for Sites that uses the EXACT same fields as the
 * single-site edit form (SiteFormPage). This eliminates all boolean
 * type conversion bugs because we use proper Switch components with
 * real boolean values — the same approach that already works for
 * single-site editing.
 *
 * How it works:
 *   1. Modal opens with all fields BLANK / indeterminate.
 *   2. User fills only the fields they want to change.
 *   3. On submit, we collect ONLY the fields that were touched
 *      (tracked via onFieldsChange + a Set of touched field names).
 *   4. We send {ids, changes} where changes contains only touched fields.
 *   5. Boolean Switch fields emit real JS booleans — no string conversion needed.
 */
import React, { useState, useRef } from 'react'
import {
  Modal, Form, Input, Select, Switch, Row, Col,
  InputNumber, Alert, Space, Typography, Divider,
} from 'antd'
import { EditOutlined, ExclamationCircleOutlined } from '@ant-design/icons'

interface Props {
  open:        boolean
  onClose:     () => void
  count:       number
  phanLoaiOpts: string[]
  onConfirm:   (changes: Record<string, unknown>) => Promise<void>
}

export default function SiteBulkEditModal({
  open, onClose, count, phanLoaiOpts, onConfirm,
}: Props) {
  const [form]    = Form.useForm()
  const [busy,    setBusy]    = useState(false)
  const [errors,  setErrors]  = useState<string[]>([])
  // Track which fields the user has actually touched/changed
  const touchedFields = useRef<Set<string>>(new Set())

  const handleFieldsChange = (changedFields: any[]) => {
    changedFields.forEach(f => {
      if (f.name) {
        const name = Array.isArray(f.name) ? f.name[0] : f.name
        touchedFields.current.add(String(name))
      }
    })
  }

  const handleOk = async () => {
    // No validateFields needed – all fields are optional in bulk edit
    const allValues = form.getFieldsValue()

    // Only send fields the user actually touched
    const changes: Record<string, unknown> = {}
    touchedFields.current.forEach(fieldName => {
      const v = allValues[fieldName]
      // Include the value even if it's false or 0 (meaningful values)
      // Only exclude undefined
      if (v !== undefined) {
        changes[fieldName] = v
      }
    })

    if (Object.keys(changes).length === 0) {
      setErrors(['Vui lòng thay đổi ít nhất một trường để cập nhật'])
      return
    }

    setBusy(true)
    setErrors([])
    try {
      await onConfirm(changes)
      handleClose()
    } catch (e: any) {
      setErrors([e?.response?.data?.detail || e?.message || 'Có lỗi xảy ra'])
    } finally {
      setBusy(false)
    }
  }

  const handleClose = () => {
    form.resetFields()
    touchedFields.current.clear()
    setErrors([])
    onClose()
  }

  return (
    <Modal
      title={
        <Space>
          <EditOutlined style={{ color: '#1890ff' }} />
          <span>Sửa hàng loạt – {count} site đã chọn</span>
        </Space>
      }
      open={open}
      onCancel={handleClose}
      onOk={handleOk}
      okText="Cập nhật tất cả"
      cancelText="Hủy"
      confirmLoading={busy}
      width={900}
      destroyOnClose
    >
      <Alert
        type="warning"
        showIcon
        icon={<ExclamationCircleOutlined />}
        style={{ marginBottom: 16 }}
        message={
          <span>
            Đang cập nhật <strong>{count}</strong> site được chọn.{' '}
            Chỉ các trường bạn <strong>thay đổi</strong> mới được cập nhật –
            trường để nguyên sẽ giữ giá trị cũ của từng site.
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

      <Form
        form={form}
        layout="vertical"
        onFieldsChange={handleFieldsChange}
      >
        {/* ── Section 1: Geographic info ── */}
        <Typography.Text strong style={{ color: '#666', fontSize: 12 }}>
          THÔNG TIN ĐỊA LÝ
        </Typography.Text>
        <Divider style={{ margin: '6px 0 12px' }} />
        <Row gutter={12}>
          <Col span={6}>
            <Form.Item name="mien" label="Miền">
              <Select allowClear placeholder="(giữ nguyên)">
                {['MB', 'MT', 'MN'].map(m => (
                  <Select.Option key={m} value={m}>{m}</Select.Option>
                ))}
              </Select>
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="site_vip" label="Site VIP">
              <Select allowClear placeholder="(giữ nguyên)">
                <Select.Option value="VIP">VIP</Select.Option>
                <Select.Option value="VVIP">VVIP</Select.Option>
              </Select>
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="lat" label="Latitude">
              <InputNumber
                style={{ width: '100%' }} precision={5} step={0.00001}
                placeholder="(giữ nguyên)"
              />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="long" label="Longitude">
              <InputNumber
                style={{ width: '100%' }} precision={5} step={0.00001}
                placeholder="(giữ nguyên)"
              />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="do_cao_dinh_cot_anten" label="Cao đỉnh cột anten (m)">
              <InputNumber style={{ width: '100%' }} min={0} placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="do_cao_cot_anten" label="Cao cột anten (m)">
              <InputNumber style={{ width: '100%' }} min={0} placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={12}>
            <Form.Item name="ma_ptm" label="Mã PTM">
              <Input placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
        </Row>

        {/* ── Section 2: Classification ── */}
        <Typography.Text strong style={{ color: '#666', fontSize: 12 }}>
          PHÂN LOẠI VÀ MORAN
        </Typography.Text>
        <Divider style={{ margin: '6px 0 12px' }} />
        <Row gutter={12}>
          <Col span={8}>
            <Form.Item name="phan_loai_tram" label="Phân loại trạm">
              <Select allowClear placeholder="(giữ nguyên)">
                {phanLoaiOpts.map(o => (
                  <Select.Option key={o} value={o}>{o}</Select.Option>
                ))}
              </Select>
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item name="moran_3g" label="MORAN 3G">
              <Select allowClear placeholder="(giữ nguyên)">
                <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                <Select.Option value="MBF HOST">MBF HOST</Select.Option>
              </Select>
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item name="moran_4g" label="MORAN 4G">
              <Select allowClear placeholder="(giữ nguyên)">
                <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                <Select.Option value="MBF HOST">MBF HOST</Select.Option>
              </Select>
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item name="moran_5g" label="MORAN 5G">
              <Select allowClear placeholder="(giữ nguyên)">
                <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                <Select.Option value="MBF HOST">MBF HOST</Select.Option>
              </Select>
            </Form.Item>
          </Col>
        </Row>

        {/* ── Section 3: Boolean flags – use Switch (real booleans) ── */}
        <Typography.Text strong style={{ color: '#666', fontSize: 12 }}>
          LOẠI TRẠM (Switch = thay đổi, bỏ qua nếu không chạm vào)
        </Typography.Text>
        <Divider style={{ margin: '6px 0 12px' }} />
        <Row gutter={12}>
          {([
            ['tram_2g',             'Trạm 2G'],
            ['tram_3g',             'Trạm 3G'],
            ['tram_4g',             'Trạm 4G'],
            ['tram_5g',             'Trạm 5G'],
            ['repeater',            'Repeater'],
            ['booster',             'Booster'],
            ['node_truyen_dan_only','Node truyền dẫn only'],
            ['tram_phu_song_tsca',  'Trạm TSCA'],
          ] as [string, string][]).map(([name, label]) => (
            <Col span={6} key={name}>
              <Form.Item name={name} label={label} valuePropName="checked">
                <Switch
                  checkedChildren="Có"
                  unCheckedChildren="Không"
                />
              </Form.Item>
            </Col>
          ))}
        </Row>

        {/* ── Section 4: Text fields ── */}
        <Typography.Text strong style={{ color: '#666', fontSize: 12 }}>
          THÔNG TIN KHÁC
        </Typography.Text>
        <Divider style={{ margin: '6px 0 12px' }} />
        <Row gutter={12}>
          <Col span={12}>
            <Form.Item name="dia_chi" label="Địa chỉ">
              <Input.TextArea rows={2} placeholder="(giữ nguyên nếu để trống)" />
            </Form.Item>
          </Col>
          <Col span={12}>
            <Form.Item name="ghi_chu" label="Ghi chú">
              <Input.TextArea rows={2} placeholder="(giữ nguyên nếu để trống)" />
            </Form.Item>
          </Col>
        </Row>
      </Form>
    </Modal>
  )
}
