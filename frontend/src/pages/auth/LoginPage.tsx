import React, { useState, useEffect } from 'react'
import { Form, Input, Button, Card, Typography, Alert, Divider } from 'antd'
import { UserOutlined, LockOutlined, SafetyCertificateOutlined } from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { login, getMe, getSsoLoginUrl } from '@/api/auth'
import { useAuthStore } from '@/store/auth'

export default function LoginPage() {
  const navigate = useNavigate()
  const setAuth  = useAuthStore((s) => s.setAuth)

  const [error,      setError]      = useState('')
  const [loading,    setLoading]    = useState(false)
  const [ssoLoading, setSsoLoading] = useState(false)
  const [ssoEnabled, setSsoEnabled] = useState(true)
  const [ssoChecked, setSsoChecked] = useState(false)

  useEffect(() => {
    // Check SSO availability on mount
    getSsoLoginUrl()
      .then((r) => {
        setSsoEnabled(r.sso_enabled)
      })
      .catch(() => {
        setSsoEnabled(false)
      })
      .finally(() => setSsoChecked(true))
  }, [])

  const onFinish = async (values: { username: string; password: string }) => {
    setLoading(true)
    setError('')
    try {
      const { access_token } = await login(values.username, values.password)
      localStorage.setItem('sl_token', access_token)
      const me = await getMe()
      setAuth(me, access_token)
      navigate('/')
    } catch {
      setError('Ten dang nhap hoac mat khau khong dung')
    } finally {
      setLoading(false)
    }
  }

  const handleSsoLogin = async () => {
    setSsoLoading(true)
    setError('')
    try {
      const { url, state } = await getSsoLoginUrl()
      // Store state + the redirect_uri we used, for validation in callback
      sessionStorage.setItem('sso_state', state)
      // Redirect browser to Keycloak login
      window.location.href = url
    } catch (e: any) {
      setError(e?.response?.data?.detail || 'Khong the ket noi SSO')
      setSsoLoading(false)
    }
  }

  return (
    <div style={{
      minHeight: '100vh',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: 'linear-gradient(135deg,#1a1a2e,#16213e,#0f3460)',
    }}>
      <Card style={{
        width: 420,
        borderRadius: 12,
        boxShadow: '0 20px 60px rgba(0,0,0,.3)',
      }}>
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <div style={{ fontSize: 48 }}>📡</div>
          <Typography.Title level={2} style={{ margin: 0 }}>SiteLink</Typography.Title>
          <Typography.Text type="secondary">
            He thong quan ly du lieu toi uu
          </Typography.Text>
        </div>

        {error && (
          <Alert
            message={error}
            type="error"
            showIcon
            style={{ marginBottom: 16 }}
            closable
            onClose={() => setError('')}
          />
        )}

        {/* ── SSO Login Button ── */}
        {ssoChecked && ssoEnabled && (
          <>
            <Button
              type="primary"
              block
              size="large"
              icon={<SafetyCertificateOutlined />}
              loading={ssoLoading}
              onClick={handleSsoLogin}
              style={{
                background: 'linear-gradient(135deg, #e65c00, #f9d423)',
                border: 'none',
                marginBottom: 8,
                fontWeight: 600,
                color: '#fff',
              }}
            >
              Dang nhap bang SSO MobiFone
            </Button>
            <Typography.Text
              type="secondary"
              style={{
                display: 'block',
                textAlign: 'center',
                fontSize: 11,
                marginBottom: 8,
              }}
            >
              Su dung tai khoan MobiFone (@mobifone.vn)
            </Typography.Text>
            <Divider plain style={{ fontSize: 12, color: '#999' }}>
              hoac dang nhap bang tai khoan local
            </Divider>
          </>
        )}

        {/* ── Local Login Form ── */}
        <Form layout="vertical" onFinish={onFinish} autoComplete="off">
          <Form.Item
            name="username"
            rules={[{ required: true, message: 'Nhap ten dang nhap' }]}
          >
            <Input
              prefix={<UserOutlined />}
              placeholder="Ten dang nhap"
              size="large"
            />
          </Form.Item>
          <Form.Item
            name="password"
            rules={[{ required: true, message: 'Nhap mat khau' }]}
          >
            <Input.Password
              prefix={<LockOutlined />}
              placeholder="Mat khau"
              size="large"
            />
          </Form.Item>
          <Form.Item>
            <Button
              type="default"
              htmlType="submit"
              block
              size="large"
              loading={loading}
            >
              Dang nhap Local
            </Button>
          </Form.Item>
        </Form>

        <Typography.Text
          type="secondary"
          style={{ display: 'block', textAlign: 'center', fontSize: 11 }}
        >
          Truy cap tu: {window.location.host}
        </Typography.Text>
      </Card>
    </div>
  )
}
