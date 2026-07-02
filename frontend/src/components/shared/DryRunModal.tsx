/**
 * DryRunModal
 * -----------
 * Generic 2-step import wizard with template download:
 *   Step 1 – upload file  → call dryRunFn  → show preview
 *   Step 2 – user confirms → call importFn → show result
 *
 * Props:
 *   templateKey: 'site' | 'cell-3g' | 'cell-4g' | 'cell-5g'
 *     When provided, shows a "Download Template" button.
 */
import React, { useState } from 'react'
import {
  Modal, Upload, Button, Steps, Descriptions, Tag,
  List, Alert, Space, Typography, Spin, Divider, Tooltip,
} from 'antd'
import {
  UploadOutlined, CheckCircleOutlined,
  ExclamationCircleOutlined, LoadingOutlined,
  DownloadOutlined, FileExcelOutlined,
} from '@ant-design/icons'

export interface DryRunPreview {
  to_create: number
  to_update: number
  sites_to_create?: number
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  preview_new_sites?: string[]
}

export interface ImportResultData {
  created: number
  updated: number
  sites_auto_created?: number
  errors: string[]
}

export type TemplateKey = 'site' | 'cell-3g' | 'cell-4g' | 'cell-5g'

interface Props {
  open:        boolean
  onClose:     () => void
  title:       string
  templateKey?: TemplateKey
  dryRunFn:   (file: File) => Promise<DryRunPreview>
  importFn:   (file: File) => Promise<ImportResultData>
  onSuccess:  () => void
}

const TEMPLATE_LABELS: Record<TemplateKey, string> = {
  'site':    'Template_Site.xlsx',
  'cell-3g': 'Template_Cell_3G.xlsx',
  'cell-4g': 'Template_Cell_4G.xlsx',
  'cell-5g': 'Template_Cell_5G.xlsx',
}

function downloadTemplate(key: TemplateKey) {
  const token = localStorage.getItem('sl_token') || ''
  // Create a temporary link – the backend serves the file with auth via Bearer
  // We use fetch+blob so we can pass Authorization header
  const url = `/api/v1/templates/${key}`
  fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  })
    .then((res) => {
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      return res.blob()
    })
    .then((blob) => {
      const link = document.createElement('a')
      link.href  = URL.createObjectURL(blob)
      link.download = TEMPLATE_LABELS[key]
      link.click()
      URL.revokeObjectURL(link.href)
    })
    .catch((err) => {
      console.error('Template download failed:', err)
      alert('Không thể tải template. Vui lòng thử lại.')
    })
}

export default function DryRunModal({
  open, onClose, title, templateKey, dryRunFn, importFn, onSuccess,
}: Props) {
  const [step,     setStep]     = useState(0)
  const [busy,     setBusy]     = useState(false)
  const [file,     setFile]     = useState<File | null>(null)
  const [preview,  setPreview]  = useState<DryRunPreview | null>(null)
  const [result,   setResult]   = useState<ImportResultData | null>(null)
  const [fatalErr, setFatalErr] = useState('')

  const reset = () => {
    setStep(0); setFile(null); setPreview(null)
    setResult(null); setFatalErr('')
  }

  const handleClose = () => { reset(); onClose() }

  const handleDryRun = async () => {
    if (!file) return
    setBusy(true)
    setFatalErr('')
    try {
      const prev = await dryRunFn(file)
      setPreview(prev)
      setStep(1)
    } catch (e: any) {
      setFatalErr(e?.response?.data?.detail || 'Cannot read file')
    } finally {
      setBusy(false)
    }
  }

  const handleConfirm = async () => {
    if (!file) return
    setBusy(true)
    try {
      const res = await importFn(file)
      setResult(res)
      setStep(2)
      onSuccess()
    } catch (e: any) {
      setFatalErr(e?.response?.data?.detail || 'Import failed')
    } finally {
      setBusy(false)
    }
  }

  const footer = () => {
    if (step === 0) return (
      <Space>
        <Button onClick={handleClose}>Huy</Button>
        <Button
          type="primary"
          disabled={!file}
          loading={busy}
          onClick={handleDryRun}
        >
          Kiểm tra file
        </Button>
      </Space>
    )
    if (step === 1) return (
      <Space>
        <Button onClick={reset}>Chon lai file</Button>
        <Button onClick={handleClose}>Huy</Button>
        <Button
          type="primary"
          loading={busy}
          onClick={handleConfirm}
          disabled={
            (preview?.to_create ?? 0) + (preview?.to_update ?? 0) === 0
          }
        >
          Xác nhận import
        </Button>
      </Space>
    )
    return (
      <Button type="primary" onClick={handleClose}>Đóng</Button>
    )
  }

  return (
    <Modal
      title={title}
      open={open}
      onCancel={handleClose}
      footer={footer()}
      width={700}
      destroyOnClose
    >
      <Steps
        current={step}
        size="small"
        style={{ marginBottom: 24 }}
        items={[
          { title: 'Chọn file' },
          { title: 'Xem trước' },
          { title: 'Hoàn thành' },
        ]}
      />

      {/* ── Step 0: file picker ── */}
      {step === 0 && (
        <div>
          {/* Template download section */}
          {templateKey && (
            <div style={{
              background: '#f6ffed',
              border: '1px solid #b7eb8f',
              borderRadius: 6,
              padding: '10px 14px',
              marginBottom: 16,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              flexWrap: 'wrap',
              gap: 8,
            }}>
              <Space>
                <FileExcelOutlined style={{ color: '#52c41a', fontSize: 18 }} />
                <div>
                  <Typography.Text strong style={{ fontSize: 13 }}>
                    Chưa có file mẫu?
                  </Typography.Text>
                  <br />
                  <Typography.Text type="secondary" style={{ fontSize: 11 }}>
                    Tải file Excel mẫu, điền dữ liệu và import lên hệ thống
                  </Typography.Text>
                </div>
              </Space>
              <Tooltip title={`Tải ${TEMPLATE_LABELS[templateKey]}`}>
                <Button
                  icon={<DownloadOutlined />}
                  size="small"
                  style={{
                    background: '#52c41a',
                    borderColor: '#52c41a',
                    color: '#fff',
                  }}
                  onClick={() => downloadTemplate(templateKey)}
                >
                  Tải file mẫu
                </Button>
              </Tooltip>
            </div>
          )}

          <Divider style={{ margin: '0 0 16px' }} />

          {fatalErr && (
            <Alert
              message={fatalErr}
              type="error"
              showIcon
              style={{ marginBottom: 12 }}
            />
          )}

          <Upload
            accept=".xlsx,.xls"
            showUploadList={Boolean(file)}
            maxCount={1}
            beforeUpload={(f) => { setFile(f); return false }}
            onRemove={() => setFile(null)}
          >
            <Button icon={<UploadOutlined />} size="large">
              Chọn file Excel để import
            </Button>
          </Upload>

          {file && (
            <Typography.Text
              type="secondary"
              style={{ marginTop: 8, display: 'block' }}
            >
              Đã chọn: <strong>{file.name}</strong>{' '}
              ({(file.size / 1024).toFixed(1)} KB)
            </Typography.Text>
          )}

          {busy && (
            <div style={{ textAlign: 'center', marginTop: 16 }}>
              <Spin indicator={<LoadingOutlined spin />} />
              <div style={{ marginTop: 8 }}>Đang kiểm tra file...</div>
            </div>
          )}
        </div>
      )}

      {/* ── Step 1: preview ── */}
      {step === 1 && preview && (
        <div>
          <Descriptions bordered size="small" column={2} style={{ marginBottom: 16 }}>
            <Descriptions.Item label="Sẽ tạo mới">
              <Tag color="green">{preview.to_create}</Tag>
            </Descriptions.Item>
            <Descriptions.Item label="Sẽ cập nhật">
              <Tag color="blue">{preview.to_update}</Tag>
            </Descriptions.Item>
            {preview.sites_to_create !== undefined && (
              <Descriptions.Item label="Site sẽ tự động tạo">
                <Tag color="purple">{preview.sites_to_create}</Tag>
              </Descriptions.Item>
            )}
            <Descriptions.Item label="Đang có lỗi / cảnh báo">
              <Tag color={preview.errors > 0 ? 'red' : 'default'}>
                {preview.errors}
              </Tag>
            </Descriptions.Item>
          </Descriptions>

          {preview.preview_create.length > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                <CheckCircleOutlined style={{ color: '#52c41a' }} />{' '}
                Sẽ tạo mới (mẫu):
              </Typography.Text>
              <List
                size="small"
                dataSource={preview.preview_create}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
              {preview.to_create > 5 && (
                <Typography.Text type="secondary">
                  ... và {preview.to_create - 5} bản ghi khác
                </Typography.Text>
              )}
            </div>
          )}

          {preview.preview_update.length > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                <CheckCircleOutlined style={{ color: '#1890ff' }} />{' '}
                Sẽ cập nhật (mẫu):
              </Typography.Text>
              <List
                size="small"
                dataSource={preview.preview_update}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </div>
          )}

          {(preview.preview_new_sites?.length ?? 0) > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                Site sẽ tự động tạo (mẫu):
              </Typography.Text>
              <List
                size="small"
                dataSource={preview.preview_new_sites}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </div>
          )}

          {preview.error_details.length > 0 && (
            <Alert
              type="warning"
              showIcon
              icon={<ExclamationCircleOutlined />}
              message={`${preview.errors} dòng có lỗi / cảnh báo (sẽ bị bỏ qua hoặc giữ nguyên)`}
              description={
                <div style={{ maxHeight: 150, overflowY: 'auto' }}>
                  {preview.error_details.slice(0, 20).map((e, i) => (
                    <div
                      key={i}
                      style={{ fontSize: 12, fontFamily: 'monospace', marginBottom: 2 }}
                    >
                      {e}
                    </div>
                  ))}
                  {preview.error_details.length > 20 && (
                    <div style={{ color: '#999' }}>
                      ... va {preview.error_details.length - 20} loi khac
                    </div>
                  )}
                </div>
              }
            />
          )}
        </div>
      )}

      {/* ── Step 2: result ── */}
      {step === 2 && result && (
        <div>
          <Alert
            type="success"
            showIcon
            message="Import hoàn thành"
            description={
              <div>
                <div>Đã tạo mới: <strong>{result.created}</strong></div>
                <div>Đã cập nhật: <strong>{result.updated}</strong></div>
                {(result.sites_auto_created ?? 0) > 0 && (
                  <div>
                    Site tự động tạo:{' '}
                    <strong>{result.sites_auto_created}</strong>
                  </div>
                )}
                {result.errors.length > 0 && (
                  <div style={{ marginTop: 8 }}>
                    <Typography.Text type="danger">
                      {result.errors.length} lỗi:
                    </Typography.Text>
                    <div style={{ maxHeight: 120, overflowY: 'auto' }}>
                      {result.errors.slice(0, 10).map((e, i) => (
                        <div
                          key={i}
                          style={{ fontSize: 12, fontFamily: 'monospace' }}
                        >
                          {e}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            }
          />
        </div>
      )}
    </Modal>
  )
}
