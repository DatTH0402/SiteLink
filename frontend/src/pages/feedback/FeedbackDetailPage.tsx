import React, { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import {
  Alert, Avatar, Button, Card, Checkbox, Col, DatePicker, Descriptions, Input, Modal,
  Popconfirm, Rate, Row, Select, Space, Spin, Tag, Typography, message,
} from 'antd'
import type { UploadFile } from 'antd/es/upload/interface'
import {
  ArrowLeftOutlined, DeleteOutlined, LockOutlined, PaperClipOutlined, ReloadOutlined, SendOutlined,
} from '@ant-design/icons'
import dayjs from 'dayjs'
import { useAuthStore } from '@/store/auth'
import {
  FbAttachment, FbDetail, FbEvent, addComment, closeTicket, deleteAttachment, deleteTicket,
  errText, getAssignees, getTicket, notifyFeedbackChanged, openAttachment, rateTicket,
  reopenTicket, updateTicket, uploadAttachments,
} from '@/api/feedback'
import {
  CategoryTag, PriorityTag, StatusTag, categoryOptions, describeEvent, fmtDt, fmtSize,
  priorityOptions, statusOptions,
} from '@/components/feedback/meta'
import { AttachmentPicker, MAX_FILES, filesFromPaste, toRawFiles } from '@/components/feedback/AttachmentPicker'

function Attachments({ items, canDelete, onDeleted }: {
  items: FbAttachment[]; canDelete: (a: FbAttachment) => boolean; onDeleted: () => void
}) {
  if (!items.length) return null
  return (
    <Space size={[6, 6]} wrap style={{ marginTop: 8 }}>
      {items.map((a) => (
        <Tag key={a.id} icon={<PaperClipOutlined />} style={{ padding: '2px 8px' }}
             closable={canDelete(a)}
             onClose={(e) => {
               e.preventDefault()
               Modal.confirm({
                 title: 'Xóa tệp đính kèm?', content: a.filename, okText: 'Xóa', cancelText: 'Hủy',
                 onOk: async () => {
                   try { await deleteAttachment(a.id); onDeleted() }
                   catch (err: any) { message.error(errText(err)) }
                 },
               })
             }}>
          <a onClick={() => openAttachment(a, !a.is_image).catch(() => message.error('Không tải được tệp'))}>
            {a.filename}
          </a>
          <span style={{ color: '#999', marginLeft: 4 }}>({fmtSize(a.size)})</span>
        </Tag>
      ))}
    </Space>
  )
}

export default function FeedbackDetailPage() {
  const { id } = useParams()
  const tid = Number(id)
  const navigate = useNavigate()
  const user = useAuthStore((s) => s.user)
  const isAdmin = user?.role === 'admin'

  const [t, setT] = useState<FbDetail | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [assignees, setAssignees] = useState<{ id: number; name: string }[]>([])
  const busyRef = useRef(false)
  const replyBox = useRef<any>(null)

  // reply box
  const [reply, setReply] = useState('')
  const [internal, setInternal] = useState(false)
  const [rfiles, setRfiles] = useState<UploadFile[]>([])
  const [sending, setSending] = useState(false)

  // admin panel
  const [pStatus, setPStatus] = useState('new')
  const [pPriority, setPPriority] = useState('normal')
  const [pCategory, setPCategory] = useState('help')
  const [pAssignee, setPAssignee] = useState<number | null>(null)
  const [pDue, setPDue] = useState<dayjs.Dayjs | null>(null)
  const [pResolution, setPResolution] = useState('')
  const [saving, setSaving] = useState(false)

  // owner actions
  const [reopenOpen, setReopenOpen] = useState(false)
  const [reopenReason, setReopenReason] = useState('')
  const [rating, setRating] = useState(0)
  const [ratingText, setRatingText] = useState('')

  const load = useCallback(async (silent = false) => {
    if (!silent) setLoading(true)
    try {
      setT(await getTicket(tid))
      setError('')
    } catch (e: any) {
      if (!silent) setError(errText(e, 'Không tải được yêu cầu'))
    } finally {
      if (!silent) setLoading(false)
    }
  }, [tid])

  useEffect(() => { load() }, [load])
  useEffect(() => { if (isAdmin) getAssignees().then(setAssignees).catch(() => {}) }, [isAdmin])
  useEffect(() => {
    const h = window.setInterval(() => { if (!document.hidden && !busyRef.current) load(true) }, 30_000)
    return () => window.clearInterval(h)
  }, [load])

  // keep the admin panel in sync with the server state
  const syncKey = t ? `${t.status}|${t.priority}|${t.category}|${t.assignee_id}|${t.due_date}|${t.resolution}` : ''
  useEffect(() => {
    if (!t) return
    setPStatus(t.status); setPPriority(t.priority); setPCategory(t.category)
    setPAssignee(t.assignee_id ?? null); setPDue(t.due_date ? dayjs(t.due_date) : null)
    setPResolution(t.resolution || '')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [syncKey])

  const after = async () => { await load(true); notifyFeedbackChanged() }

  const send = async () => {
    if (!reply.trim()) { message.warning('Vui lòng nhập nội dung'); return }
    setSending(true); busyRef.current = true
    try {
      const ev = await addComment(tid, { body: reply.trim(), is_internal: isAdmin && internal })
      const raw = toRawFiles(rfiles)
      if (raw.length) {
        try { await uploadAttachments(tid, raw, ev.id) }
        catch { message.warning('Đã gửi phản hồi nhưng tải tệp đính kèm thất bại') }
      }
      setReply(''); setRfiles([]); setInternal(false)
      await after()
    } catch (e: any) { message.error(errText(e)) }
    finally { setSending(false); busyRef.current = false }
  }

  const saveAdmin = async () => {
    if (!t) return
    const ch: Record<string, unknown> = {}
    if (pStatus !== t.status) ch.status = pStatus
    if (pPriority !== t.priority) ch.priority = pPriority
    if (pCategory !== t.category) ch.category = pCategory
    if ((pAssignee ?? null) !== (t.assignee_id ?? null)) ch.assignee_id = pAssignee
    const dueNew = pDue ? pDue.format('YYYY-MM-DD') : null
    const dueOld = t.due_date ? dayjs(t.due_date).format('YYYY-MM-DD') : null
    if (dueNew !== dueOld) ch.due_date = pDue ? pDue.endOf('day').toISOString() : null
    if (pResolution.trim() !== (t.resolution || '').trim()) ch.resolution = pResolution
    if (!Object.keys(ch).length) { message.info('Không có thay đổi'); return }
    if ((ch.status === 'resolved' || ch.status === 'rejected') && !pResolution.trim()) {
      message.warning('Vui lòng nhập kết quả xử lý / lý do để người gửi biết'); return
    }
    setSaving(true); busyRef.current = true
    try { setT(await updateTicket(tid, ch)); message.success('Đã cập nhật'); notifyFeedbackChanged() }
    catch (e: any) { message.error(errText(e)) }
    finally { setSaving(false); busyRef.current = false }
  }

  const quick = async (changes: Record<string, unknown>, focus = false) => {
    try {
      setT(await updateTicket(tid, changes)); notifyFeedbackChanged()
      if (focus) replyBox.current?.focus?.()
    } catch (e: any) { message.error(errText(e)) }
  }

  const doClose = async () => {
    try { setT(await closeTicket(tid)); notifyFeedbackChanged() } catch (e: any) { message.error(errText(e)) }
  }
  const doReopen = async () => {
    try {
      setT(await reopenTicket(tid, reopenReason.trim() || undefined))
      setReopenOpen(false); setReopenReason(''); notifyFeedbackChanged()
    } catch (e: any) { message.error(errText(e)) }
  }
  const doRate = async () => {
    if (!rating) { message.warning('Hãy chọn số sao'); return }
    try { setT(await rateTicket(tid, rating, ratingText.trim() || undefined)); message.success('Cảm ơn bạn đã đánh giá!') }
    catch (e: any) { message.error(errText(e)) }
  }
  const doDelete = async () => {
    try { await deleteTicket(tid); notifyFeedbackChanged(); navigate('/feedback') }
    catch (e: any) { message.error(errText(e)) }
  }

  if (loading) return <div style={{ textAlign: 'center', padding: 60 }}><Spin size="large" /></div>
  if (error || !t) {
    return (
      <div>
        <Alert type="error" showIcon message={error || 'Không tìm thấy yêu cầu'} style={{ marginBottom: 12 }} />
        <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/feedback')}>Quay lại danh sách</Button>
      </div>
    )
  }

  const isDone = ['resolved', 'closed', 'rejected'].includes(t.status)
  const canDeleteAtt = (a: FbAttachment) => isAdmin || a.uploaded_by === user?.id
  const ticketLevelAtts = t.attachments.filter((a) => !a.event_id)

  const renderEvent = (e: FbEvent) => {
    if (e.kind === 'comment' || e.kind === 'note') {
      const fromAdmin = e.user_role === 'admin'
      const note = e.kind === 'note'
      return (
        <div key={e.id} style={{ display: 'flex', gap: 10, marginBottom: 12 }}>
          <Avatar style={{ background: fromAdmin ? '#1677ff' : '#8c8c8c', flexShrink: 0 }}>
            {(e.user_name || '?').charAt(0).toUpperCase()}
          </Avatar>
          <div style={{
            flex: 1, borderRadius: 8, padding: '8px 12px',
            background: note ? '#fffbe6' : fromAdmin ? '#e6f4ff' : '#fafafa',
            border: `1px solid ${note ? '#ffe58f' : fromAdmin ? '#91caff' : '#f0f0f0'}`,
          }}>
            <Space size={8} wrap>
              <strong>{e.user_name}</strong>
              {fromAdmin && <Tag color="blue" style={{ margin: 0 }}>Hỗ trợ</Tag>}
              {note && <Tag color="gold" icon={<LockOutlined />} style={{ margin: 0 }}>Ghi chú nội bộ</Tag>}
              <Typography.Text type="secondary" style={{ fontSize: 12 }}>{fmtDt(e.created_at)}</Typography.Text>
            </Space>
            <div style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word', marginTop: 4 }}>{e.body}</div>
            <Attachments items={t.attachments.filter((a) => a.event_id === e.id)}
                         canDelete={canDeleteAtt} onDeleted={() => load(true)} />
          </div>
        </div>
      )
    }
    return (
      <div key={e.id} style={{ textAlign: 'center', margin: '8px 0', fontSize: 12, color: '#8c8c8c' }}>
        <b>{e.user_name}</b> {describeEvent(e)} · {fmtDt(e.created_at)}
        {e.body && e.kind !== 'edit' && (
          <div style={{ fontStyle: 'italic', whiteSpace: 'pre-wrap' }}>“{e.body}”</div>
        )}
      </div>
    )
  }

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 12 }} gutter={[8, 8]}>
        <Col>
          <Space align="center" wrap>
            <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/feedback')}>Danh sách</Button>
            <Typography.Title level={4} style={{ margin: 0 }}>{t.code} · {t.title}</Typography.Title>
            <StatusTag v={t.status} /><PriorityTag v={t.priority} /><CategoryTag v={t.category} />
            {t.overdue && <Tag color="red">Quá hạn</Tag>}
          </Space>
        </Col>
        <Col>
          <Space wrap>
            <Button icon={<ReloadOutlined />} onClick={() => load(true)} />
            {isDone && (t.is_owner || isAdmin) && (
              <Button onClick={() => setReopenOpen(true)}>Mở lại</Button>
            )}
            {t.status === 'resolved' && t.is_owner && (
              <Button type="primary" onClick={doClose}>Xác nhận đã xong & đóng</Button>
            )}
            {!isDone && t.is_owner && (
              <Popconfirm title="Đóng yêu cầu này?" okText="Đóng" cancelText="Hủy" onConfirm={doClose}>
                <Button>Đóng yêu cầu</Button>
              </Popconfirm>
            )}
            {isAdmin && (
              <Popconfirm title="Xóa vĩnh viễn yêu cầu này?" okText="Xóa" cancelText="Hủy" onConfirm={doDelete}>
                <Button danger icon={<DeleteOutlined />} />
              </Popconfirm>
            )}
          </Space>
        </Col>
      </Row>

      <Row gutter={16}>
        <Col xs={24} lg={16}>
          <Card size="small" title="Nội dung yêu cầu" style={{ marginBottom: 12 }}>
            <div style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>{t.description}</div>
            <Attachments items={ticketLevelAtts} canDelete={canDeleteAtt} onDeleted={() => load(true)} />
          </Card>

          {t.resolution && (
            <Alert type={t.status === 'rejected' ? 'error' : 'success'} showIcon style={{ marginBottom: 12 }}
              message={t.status === 'rejected' ? 'Lý do từ chối' : 'Kết quả xử lý'}
              description={<span style={{ whiteSpace: 'pre-wrap' }}>{t.resolution}</span>} />
          )}

          {t.is_owner && ['resolved', 'closed'].includes(t.status) && (
            <Card size="small" style={{ marginBottom: 12 }} title="Đánh giá kết quả xử lý">
              {t.rating ? (
                <Space direction="vertical" size={2}>
                  <Rate disabled value={t.rating} />
                  {t.rating_comment && <Typography.Text type="secondary">{t.rating_comment}</Typography.Text>}
                </Space>
              ) : (
                <Space direction="vertical" style={{ width: '100%' }}>
                  <Rate value={rating} onChange={setRating} />
                  <Input.TextArea rows={2} value={ratingText} onChange={(e) => setRatingText(e.target.value)}
                                  placeholder="Nhận xét thêm (không bắt buộc)" />
                  <Button type="primary" size="small" onClick={doRate}>Gửi đánh giá</Button>
                </Space>
              )}
            </Card>
          )}

          <Card size="small" title={`Trao đổi & lịch sử xử lý (${t.events.length})`} style={{ marginBottom: 12 }}>
            {t.events.length === 0 && <Typography.Text type="secondary">Chưa có trao đổi nào.</Typography.Text>}
            {t.events.map(renderEvent)}
          </Card>

          <Card size="small" title="Phản hồi">
            {t.status === 'closed' ? (
              <Alert type="info" showIcon message="Yêu cầu đã đóng. Bấm 'Mở lại' nếu bạn cần tiếp tục trao đổi." />
            ) : (
              <Space direction="vertical" style={{ width: '100%' }}>
                {t.status === 'waiting_user' && t.is_owner && (
                  <Alert type="warning" showIcon message="Bộ phận hỗ trợ đang chờ thông tin từ bạn. Hãy trả lời bên dưới." />
                )}
                <Input.TextArea ref={replyBox} rows={4} value={reply}
                  onChange={(e) => setReply(e.target.value)}
                  placeholder={internal ? 'Ghi chú nội bộ – người gửi sẽ KHÔNG nhìn thấy' : 'Nhập nội dung phản hồi...'}
                  style={internal ? { background: '#fffbe6' } : undefined}
                  onPaste={(e) => {
                    const add = filesFromPaste(e)
                    if (add.length) setRfiles((p) => [...p, ...add].slice(0, MAX_FILES))
                  }} />
                <AttachmentPicker files={rfiles} onChange={setRfiles} />
                <Space>
                  <Button type="primary" icon={<SendOutlined />} loading={sending} onClick={send}>Gửi</Button>
                  {isAdmin && (
                    <Checkbox checked={internal} onChange={(e) => setInternal(e.target.checked)}>
                      <LockOutlined /> Ghi chú nội bộ
                    </Checkbox>
                  )}
                </Space>
              </Space>
            )}
          </Card>
        </Col>

        <Col xs={24} lg={8}>
          {isAdmin && (
            <Card size="small" title="Xử lý yêu cầu" style={{ marginBottom: 12 }}>
              <Space wrap style={{ marginBottom: 8 }}>
                <Button size="small" onClick={() => user && quick({ assignee_id: user.id })}
                        disabled={t.assignee_id === user?.id}>Nhận xử lý</Button>
                <Button size="small" onClick={() => quick({ status: 'waiting_user' }, true)}
                        disabled={t.status === 'waiting_user'}>Cần thêm thông tin</Button>
              </Space>
              <Space direction="vertical" style={{ width: '100%' }} size={8}>
                <div><Typography.Text type="secondary">Trạng thái</Typography.Text>
                  <Select style={{ width: '100%' }} value={pStatus} onChange={setPStatus} options={statusOptions} /></div>
                <div><Typography.Text type="secondary">Ưu tiên</Typography.Text>
                  <Select style={{ width: '100%' }} value={pPriority} onChange={setPPriority} options={priorityOptions} /></div>
                <div><Typography.Text type="secondary">Phân loại</Typography.Text>
                  <Select style={{ width: '100%' }} value={pCategory} onChange={setPCategory} options={categoryOptions} /></div>
                <div><Typography.Text type="secondary">Người xử lý</Typography.Text>
                  <Select style={{ width: '100%' }} allowClear placeholder="Chưa phân công" value={pAssignee ?? undefined}
                          onChange={(v) => setPAssignee(v ?? null)}
                          options={assignees.map((a) => ({ value: a.id, label: a.name }))} /></div>
                <div><Typography.Text type="secondary">Hạn xử lý</Typography.Text>
                  <DatePicker style={{ width: '100%' }} value={pDue} onChange={(v) => setPDue(v)} format="DD/MM/YYYY" /></div>
                <div><Typography.Text type="secondary">Kết quả xử lý / lý do (người gửi sẽ thấy)</Typography.Text>
                  <Input.TextArea rows={3} value={pResolution} onChange={(e) => setPResolution(e.target.value)} /></div>
                <Button type="primary" block loading={saving} onClick={saveAdmin}>Lưu thay đổi</Button>
              </Space>
            </Card>
          )}

          <Card size="small" title="Thông tin">
            <Descriptions column={1} size="small" colon={false}
              items={[
                { key: 'by', label: 'Người gửi', children: <>{t.created_by_name}{isAdmin && t.created_by_email ? ` (${t.created_by_email})` : ''}</> },
                { key: 'as', label: 'Người xử lý', children: t.assignee_name || <span style={{ color: '#bbb' }}>Chưa phân công</span> },
                { key: 'cat', label: 'Loại', children: <CategoryTag v={t.category} /> },
                { key: 'pri', label: 'Ưu tiên', children: <PriorityTag v={t.priority} /> },
                { key: 'ref', label: 'Site/Cell liên quan', children: t.related_ref || '-' },
                { key: 'cr', label: 'Tạo lúc', children: fmtDt(t.created_at) },
                { key: 'fr', label: 'Phản hồi đầu', children: fmtDt(t.first_response_at) },
                { key: 'due', label: 'Hạn xử lý', children: <span style={{ color: t.overdue ? '#cf1322' : undefined }}>{fmtDt(t.due_date)}</span> },
                { key: 'rs', label: 'Xử lý xong', children: fmtDt(t.resolved_at) },
                { key: 'ro', label: 'Số lần mở lại', children: t.reopen_count },
                { key: 'pg', label: 'Trang gửi từ', children: t.page_url || '-' },
                ...(isAdmin ? [{ key: 'ua', label: 'Trình duyệt', children: <span style={{ fontSize: 11, wordBreak: 'break-all' }}>{t.user_agent || '-'}</span> }] : []),
              ]} />
          </Card>
        </Col>
      </Row>

      <Modal title="Mở lại yêu cầu" open={reopenOpen} onOk={doReopen} onCancel={() => setReopenOpen(false)}
             okText="Mở lại" cancelText="Hủy">
        <Input.TextArea rows={3} value={reopenReason} onChange={(e) => setReopenReason(e.target.value)}
                        placeholder="Lý do mở lại (không bắt buộc)" />
      </Modal>
    </div>
  )
}
