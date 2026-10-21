import React from 'react'
import { Button, Typography, Upload, message } from 'antd'
import type { UploadFile } from 'antd/es/upload/interface'
import { PaperClipOutlined } from '@ant-design/icons'

export const MAX_FILES = 5
export const MAX_MB = 10
const ACCEPT = '.png,.jpg,.jpeg,.gif,.webp,.pdf,.txt,.log,.csv,.xlsx,.xls,.docx,.doc,.pptx,.zip'

/** images pasted (Ctrl+V) into a text box -> UploadFile[] */
export function filesFromPaste(e: React.ClipboardEvent): UploadFile[] {
  const out: UploadFile[] = []
  Array.from(e.clipboardData?.files ?? []).forEach((f, i) => {
    if (f.type.startsWith('image/')) {
      out.push({
        uid: `paste-${Date.now()}-${i}`,
        name: f.name && f.name !== 'image.png' ? f.name : `screenshot-${Date.now()}-${i}.png`,
        status: 'done',
        originFileObj: f as any,
      })
    }
  })
  return out
}

export const toRawFiles = (files: UploadFile[]): File[] =>
  files.map((f) => f.originFileObj as File | undefined).filter((f): f is File => !!f)

interface Props {
  files: UploadFile[]
  onChange: (f: UploadFile[]) => void
  disabled?: boolean
}

export function AttachmentPicker({ files, onChange, disabled }: Props) {
  return (
    <div>
      <Upload
        multiple
        disabled={disabled}
        accept={ACCEPT}
        fileList={files}
        beforeUpload={() => false}
        onChange={({ fileList }) => {
          const ok = fileList.filter((f) => {
            const sz = f.size ?? (f.originFileObj as File | undefined)?.size ?? 0
            if (sz > MAX_MB * 1024 * 1024) {
              message.warning(`${f.name}: vượt quá ${MAX_MB} MB`)
              return false
            }
            return true
          })
          if (ok.length > MAX_FILES) message.warning(`Tối đa ${MAX_FILES} tệp mỗi lần gửi`)
          onChange(ok.slice(0, MAX_FILES))
        }}
      >
        <Button size="small" icon={<PaperClipOutlined />} disabled={disabled}>Đính kèm tệp</Button>
      </Upload>
      <Typography.Text type="secondary" style={{ fontSize: 11 }}>
        Có thể dán ảnh chụp màn hình (Ctrl+V) vào ô nội dung · tối đa {MAX_FILES} tệp, {MAX_MB} MB/tệp
        (ảnh, pdf, excel, word, zip, txt/log)
      </Typography.Text>
    </div>
  )
}
