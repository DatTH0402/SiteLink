import React, { useState } from 'react'
import { FloatButton, message } from 'antd'
import { CustomerServiceOutlined } from '@ant-design/icons'
import { useLocation, useNavigate } from 'react-router-dom'
import FeedbackFormModal from './FeedbackFormModal'

/** floating "send feedback" button available on every page (hidden on /feedback*) */
export default function FeedbackFab() {
  const [open, setOpen] = useState(false)
  const navigate = useNavigate()
  const { pathname } = useLocation()
  if (pathname.startsWith('/feedback')) return null

  return (
    <>
      <FloatButton
        type="primary" icon={<CustomerServiceOutlined />}
        tooltip="Gửi góp ý / yêu cầu hỗ trợ"
        style={{ right: 24, bottom: 24 }}
        onClick={() => setOpen(true)}
      />
      <FeedbackFormModal
        open={open}
        onClose={() => setOpen(false)}
        onCreated={(t) =>
          message.success({
            content: (
              <span>
                Đã gửi <b>{t.code}</b>.{' '}
                <a onClick={() => navigate(`/feedback/${t.id}`)}>Xem chi tiết</a>
              </span>
            ),
            duration: 6,
          })}
      />
    </>
  )
}
