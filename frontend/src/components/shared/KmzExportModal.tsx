import React, { useEffect, useState } from 'react'
import { Modal, Select, Alert, Typography, Space, Spin, message } from 'antd'
import { exportKmz, getKmzMeta } from '@/api/export'
import type { ExportScope, KmzFilters, KmzLayer, KmzMeta } from '@/api/export'

interface Props {
  open: boolean
  onClose: () => void
  layer: KmzLayer
  /** top-bar filters of the page (same object used for the Excel export) */
  filters: KmzFilters
  /** selected ids / column filters / sort (see buildExportScope) */
  scope: ExportScope
  selectedCount: number
}

const NO_ICON = '__none__'

const filterOpt = (input: string, option?: { label?: unknown }) =>
  String(option?.label ?? '').toLowerCase().includes(input.toLowerCase())

export default function KmzExportModal({
  open, onClose, layer, filters, scope, selectedCount,
}: Props) {
  const [meta,        setMeta]        = useState<KmzMeta | null>(null)
  const [loadingMeta, setLoadingMeta] = useState(false)
  const [metaError,   setMetaError]   = useState<string | null>(null)
  const [exporting,   setExporting]   = useState(false)

  const [folder,    setFolder]    = useState('tinh')
  const [colorCol,  setColorCol]  = useState('')
  const [iconCol,   setIconCol]   = useState(NO_ICON)
  const [colorMode, setColorMode] = useState('auto')
  const [opacity,   setOpacity]   = useState('35')

  useEffect(() => {
    if (!open || meta) return
    let cancelled = false
    setLoadingMeta(true)
    setMetaError(null)
    getKmzMeta(layer)
      .then((m) => {
        if (cancelled) return
        setMeta(m)
        setFolder(m.default_folder)
        setColorCol(m.default_color)
        setIconCol(m.default_icon || NO_ICON)
        setColorMode(m.default_color_mode)
        setOpacity(m.default_opacity)
      })
      .catch((e: any) => { if (!cancelled) setMetaError(e?.message || 'Không tải được cấu hình KMZ') })
      .finally(() => { if (!cancelled) setLoadingMeta(false) })
    return () => { cancelled = true }
  }, [open, layer])

  const handleExport = async () => {
    if (!meta) return
    setExporting(true)
    try {
      const d = new Date()
      const date = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`
      const options: Record<string, unknown> = {
        folder, color_col: colorCol, color_mode: colorMode, date,
      }
      if (meta.has_icon)    options.icon_col = iconCol === NO_ICON ? '' : iconCol
      if (meta.has_opacity) options.opacity  = opacity

      const res = await exportKmz(layer, filters, scope, options)
      const detail = res.rows != null && res.valid != null
        ? ` (${res.valid.toLocaleString('vi-VN')}/${res.rows.toLocaleString('vi-VN')} dòng có tọa độ)`
        : ''
      message.success(`Xuất KMZ thành công${detail}: ${res.filename}`)
      onClose()
    } catch (e: any) {
      message.error(e?.message || 'Xuất KMZ thất bại')
    } finally {
      setExporting(false)
    }
  }

  const label = (text: string) => (
    <Typography.Text strong style={{ display: 'block', marginBottom: 4 }}>{text}</Typography.Text>
  )

  return (
    <Modal
      title={`Xuất KMZ Google Earth – ${meta?.title ?? ''}`}
      open={open}
      onCancel={onClose}
      onOk={handleExport}
      okText="🚀 Xuất KMZ"
      cancelText="Hủy"
      confirmLoading={exporting}
      okButtonProps={{ disabled: !meta }}
      width={680}
    >
      {loadingMeta && <div style={{ textAlign: 'center', padding: 24 }}><Spin /></div>}
      {metaError && <Alert type="error" showIcon message={metaError} />}

      {meta && (
        <Space direction="vertical" size={12} style={{ width: '100%' }}>
          <Alert
            type="info" showIcon
            message={selectedCount > 0
              ? `Sẽ xuất ${selectedCount.toLocaleString('vi-VN')} dòng đã chọn.`
              : 'Sẽ xuất toàn bộ dữ liệu theo bộ lọc hiện tại (gồm cả bộ lọc cột). Không có bộ lọc = xuất tất cả.'}
            description={meta.note}
          />

          <div>
            {label('Cột Folder CẤP 1 (Mặc định: Tỉnh):')}
            <Select style={{ width: '100%' }} value={folder} onChange={setFolder}
                    options={meta.folders} />
          </div>

          <div>
            {label(meta.color_label)}
            <Select style={{ width: '100%' }} showSearch optionFilterProp="label"
                    filterOption={filterOpt}
                    value={colorCol} onChange={setColorCol} options={meta.color_columns} />
          </div>

          {meta.has_icon && (
            <div>
              {label(meta.icon_label)}
              <Select style={{ width: '100%' }} showSearch optionFilterProp="label"
                      filterOption={filterOpt}
                      value={iconCol} onChange={setIconCol}
                      options={[
                        { value: NO_ICON, label: '(Không dùng icon - Mặc định hình tròn)' },
                        ...meta.icon_columns,
                      ]} />
            </div>
          )}

          <div>
            {label('Kiểu phối màu (Color Mode):')}
            <Select style={{ width: '100%' }} value={colorMode} onChange={setColorMode}
                    options={meta.color_modes} />
          </div>

          {meta.has_opacity && (
            <div>
              {label('Độ trong suốt cánh cell (Thân cell):')}
              <Select style={{ width: '100%' }} value={opacity} onChange={setOpacity}
                      options={meta.opacities} />
            </div>
          )}

          <Typography.Text type="secondary" style={{ fontSize: 12 }}>
            Tên file: KMZ-&lt;Site|CellXG&gt;-&lt;folder cấp 1&gt;-&lt;cột màu&gt;[-icon_&lt;cột icon&gt;]-&lt;yyyymmdd&gt;.kmz
          </Typography.Text>
        </Space>
      )}
    </Modal>
  )
}
