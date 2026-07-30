/**
 * CellBulkEditModal
 * -----------------
 * Generic bulk-edit modal for Cell 3G / 4G / 5G.
 * Uses the same field tracking approach as SiteBulkEditModal.
 * Only touched fields are sent in the changes payload.
 *
 * Props:
 *   tech: '3g' | '4g' | '5g'  – controls which tech-specific fields to show
 */
import React, { useState, useRef } from 'react'
import {
  Modal, Form, Input, Select, Row, Col,
  InputNumber, Alert, Space, Typography, Divider,
} from 'antd'
import { EditOutlined, ExclamationCircleOutlined } from '@ant-design/icons'
import { azimuthValidator } from '@/utils/validators'

export type CellTech = '3g' | '4g' | '5g'

interface Props {
  open:        boolean
  onClose:     () => void
  count:       number
  tech:        CellTech
  antennaList: { id: number; name: string }[]
  onConfirm:   (changes: Record<string, unknown>) => Promise<void>
}

const VENDORS   = ['Ericsson', 'Nokia', 'Huawei', 'ZTE', 'Samsung']
const MIMOS     = ['2x2', '4x4', '8x8']
const MORANS    = ['VNPT HOST', 'MBF HOST']
const VUNGS     = ['Indoor', 'Outdoor']
const CELL_VIPS = ['VIP', 'VVIP']

const CHUNG_ANTEN: Record<CellTech, string[]> = {
  '3g': ['3G', '3G/4G', '2G/3G/4G', '3G/4G/5G', '3G/5G'],
  '4g': ['4G', '2G/4G', '3G/4G', '2G/3G/4G', '4G/5G'],
  '5g': [],
}

export default function CellBulkEditModal({
  open, onClose, count, tech, antennaList, onConfirm,
}: Props) {
  const [form]   = Form.useForm()
  const [busy,   setBusy]   = useState(false)
  const [errors, setErrors] = useState<string[]>([])
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
    try { await form.validateFields() } catch { return }
    const allValues = form.getFieldsValue()

    const changes: Record<string, unknown> = {}
    touchedFields.current.forEach(fieldName => {
      const v = allValues[fieldName]
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

  const techLabel = tech.toUpperCase()

  return (
    <Modal
      title={
        <Space>
          <EditOutlined style={{ color: '#1890ff' }} />
          <span>Sửa hàng loạt – {count} Cell {techLabel} đã chọn</span>
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
            Đang cập nhật <strong>{count}</strong> Cell {techLabel} được chọn.{' '}
            Chỉ các trường bạn <strong>thay đổi</strong> mới được cập nhật.
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

      <Form form={form} layout="vertical" onFieldsChange={handleFieldsChange}>

        {/* ── Common fields ── */}
        <Typography.Text strong style={{ color: '#666', fontSize: 12 }}>
          THÔNG TIN CHUNG
        </Typography.Text>
        <Divider style={{ margin: '6px 0 12px' }} />
        <Row gutter={12}>
          <Col span={6}>
            <Form.Item name="cell_vip" label="Cell VIP">
              <Select allowClear placeholder="(giữ nguyên)">
                {CELL_VIPS.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="moran" label="MORAN">
              <Select allowClear placeholder="(giữ nguyên)">
                {MORANS.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="vung_phu_song" label="Vùng phủ sóng">
              <Select allowClear placeholder="(giữ nguyên)">
                {VUNGS.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="vendor" label="Vendor">
              <Select allowClear placeholder="(giữ nguyên)">
                {VENDORS.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="mimo" label="MIMO">
              <Select allowClear placeholder="(giữ nguyên)">
                {MIMOS.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          {tech !== '5g' && (
            <Col span={6}>
              <Form.Item name="chung_anten" label="Chung anten">
                <Select allowClear placeholder="(giữ nguyên)">
                  {CHUNG_ANTEN[tech].map(v => (
                    <Select.Option key={v} value={v}>{v}</Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
          )}
          {tech === '5g' && (
            <Col span={6}>
              <Form.Item name="mu_mimo" label="MU-MIMO">
                <Select allowClear placeholder="(giữ nguyên)">
                  <Select.Option value="Yes">Yes</Select.Option>
                  <Select.Option value="No">No</Select.Option>
                </Select>
              </Form.Item>
            </Col>
          )}
          <Col span={6}>
            <Form.Item
              name="azimuth"
              label="Azimuth (0–359)"
              rules={[{ validator: azimuthValidator }]}
            >
              <InputNumber style={{ width: '100%' }} min={0} max={359} placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="m_tilt" label="M-tilt">
              <InputNumber style={{ width: '100%' }} placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="e_tilt" label="E-Tilt">
              <InputNumber style={{ width: '100%' }} placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="total_tilt" label="Total Tilt">
              <InputNumber style={{ width: '100%' }} placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="do_cao_anten" label="Độ cao anten (m)">
              <InputNumber style={{ width: '100%' }} placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
        </Row>

        {/* ── Antenna / Equipment ── */}
        <Typography.Text strong style={{ color: '#666', fontSize: 12 }}>
          THIẾT BỊ
        </Typography.Text>
        <Divider style={{ margin: '6px 0 12px' }} />
        <Row gutter={12}>
          <Col span={24}>
            <Form.Item name="loai_anten" label="Loại Anten">
              <Select
                showSearch allowClear placeholder="(giữ nguyên)"
                filterOption={(i, o) =>
                  String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())
                }
              >
                {antennaList.map(a => (
                  <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>
                ))}
              </Select>
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item name="baseband" label="Baseband">
              <Input placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item name="rf" label="RF">
              <Input placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item name="bbu_name" label="BBUname">
              <Input placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={16}>
            <Form.Item name="cell_status" label="Cell status (at dump time)">
              <Input placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
        </Row>
      </Form>
    </Modal>
  )
}
