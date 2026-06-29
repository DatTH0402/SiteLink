/**
 * DryRunModal
 * -----------
 * Generic 2-step import wizard:
 *   Step 1 – upload file  → call dryRunFn  → show preview
 *   Step 2 – user confirms → call importFn → show result
 */
import React, { useState } from 'react'
import {
  Modal, Upload, Button, Steps, Descriptions, Tag,
  List, Alert, Space, Typography, Spin,
} from 'antd'
import {
  UploadOutlined, CheckCircleOutlined,
  ExclamationCircleOutlined, LoadingOutlined,
} from '@ant-design/icons'

export interface DryRunPreview {
  to_create: number
  to_update: number
  sites_to_create?: number   // cells only
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

interface Props {
  open: boolean
  onClose: () => void
  title: string
  dryRunFn:  (file: File) => Promise<DryRunPreview>
  importFn:  (file: File) => Promise<ImportResultData>
  onSuccess: () => void
}

export default function DryRunModal({
  open, onClose, title, dryRunFn, importFn, onSuccess,
}: Props) {
  const [step,     setStep]     = useState(0)       // 0=upload 1=preview 2=done
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

  // Step 0 → 1 : dry-run
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

  // Step 1 → 2 : commit
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
        <Button type="primary" disabled={!file} loading={busy}
                onClick={handleDryRun}>
          Kiem tra file
        </Button>
      </Space>
    )
    if (step === 1) return (
      <Space>
        <Button onClick={reset}>Chon lai file</Button>
        <Button onClick={handleClose}>Huy</Button>
        <Button type="primary" loading={busy} onClick={handleConfirm}
                disabled={(preview?.to_create ?? 0) + (preview?.to_update ?? 0) === 0}>
          Xac nhan import
        </Button>
      </Space>
    )
    return <Button type="primary" onClick={handleClose}>Dong</Button>
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
          { title: 'Chon file' },
          { title: 'Xem truoc' },
          { title: 'Hoan thanh' },
        ]}
      />

      {/* ── Step 0 : file picker ──────────────────────────────────────── */}
      {step === 0 && (
        <div>
          {fatalErr && (
            <Alert message={fatalErr} type="error" showIcon
                   style={{ marginBottom: 12 }} />
          )}
          <Upload
            accept=".xlsx,.xls"
            showUploadList={Boolean(file)}
            maxCount={1}
            beforeUpload={(f) => { setFile(f); return false }}
            onRemove={() => setFile(null)}
          >
            <Button icon={<UploadOutlined />}>Chon file Excel</Button>
          </Upload>
          {file && (
            <Typography.Text type="secondary" style={{ marginTop: 8, display: 'block' }}>
              Da chon: <strong>{file.name}</strong>
            </Typography.Text>
          )}
          {busy && (
            <div style={{ textAlign: 'center', marginTop: 16 }}>
              <Spin indicator={<LoadingOutlined spin />} />
              <div>Dang kiem tra file...</div>
            </div>
          )}
        </div>
      )}

      {/* ── Step 1 : preview ─────────────────────────────────────────── */}
      {step === 1 && preview && (
        <div>
          <Descriptions bordered size="small" column={2}
                        style={{ marginBottom: 16 }}>
            <Descriptions.Item label="Se tao moi">
              <Tag color="green">{preview.to_create}</Tag>
            </Descriptions.Item>
            <Descriptions.Item label="Se cap nhat">
              <Tag color="blue">{preview.to_update}</Tag>
            </Descriptions.Item>
            {preview.sites_to_create !== undefined && (
              <Descriptions.Item label="Site se tu dong tao">
                <Tag color="purple">{preview.sites_to_create}</Tag>
              </Descriptions.Item>
            )}
            <Descriptions.Item label="Dong co loi">
              <Tag color={preview.errors > 0 ? 'red' : 'default'}>
                {preview.errors}
              </Tag>
            </Descriptions.Item>
          </Descriptions>

          {preview.preview_create.length > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                <CheckCircleOutlined style={{ color: '#52c41a' }} /> Se tao moi (mau):
              </Typography.Text>
              <List size="small" dataSource={preview.preview_create}
                    renderItem={(item) => <List.Item>{item}</List.Item>} />
              {preview.to_create > 5 && (
                <Typography.Text type="secondary">
                  ... va {preview.to_create - 5} ban ghi khac
                </Typography.Text>
              )}
            </div>
          )}

          {preview.preview_update.length > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                <CheckCircleOutlined style={{ color: '#1890ff' }} /> Se cap nhat (mau):
              </Typography.Text>
              <List size="small" dataSource={preview.preview_update}
                    renderItem={(item) => <List.Item>{item}</List.Item>} />
            </div>
          )}

          {(preview.preview_new_sites?.length ?? 0) > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Typography.Text strong>
                Site se duoc tu dong tao (mau):
              </Typography.Text>
              <List size="small" dataSource={preview.preview_new_sites}
                    renderItem={(item) => <List.Item>{item}</List.Item>} />
            </div>
          )}

          {preview.error_details.length > 0 && (
            <Alert
              type="warning"
              showIcon
              icon={<ExclamationCircleOutlined />}
              message={`${preview.errors} dong co loi (se bi bo qua)`}
              description={
                <div style={{ maxHeight: 150, overflowY: 'auto' }}>
                  {preview.error_details.slice(0, 20).map((e, i) => (
                    <div key={i} style={{ fontSize: 12, fontFamily: 'monospace' }}>
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

      {/* ── Step 2 : result ───────────────────────────────────────────── */}
      {step === 2 && result && (
        <div>
          <Alert
            type="success"
            showIcon
            message="Import hoan thanh"
            description={
              <div>
                <div>Da tao moi: <strong>{result.created}</strong></div>
                <div>Da cap nhat: <strong>{result.updated}</strong></div>
                {(result.sites_auto_created ?? 0) > 0 && (
                  <div>
                    Site tu dong tao:{' '}
                    <strong>{result.sites_auto_created}</strong>
                  </div>
                )}
                {result.errors.length > 0 && (
                  <div style={{ marginTop: 8 }}>
                    <Typography.Text type="danger">
                      {result.errors.length} loi:
                    </Typography.Text>
                    <div style={{ maxHeight: 120, overflowY: 'auto' }}>
                      {result.errors.slice(0, 10).map((e, i) => (
                        <div key={i} style={{ fontSize: 12, fontFamily: 'monospace' }}>
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
