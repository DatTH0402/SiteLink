/**
 * SsoCallbackPage
 * ---------------
 * Keycloak redirects the browser to:
 *   <origin>/sitelink/sso/callback?code=xxx&state=xxx
 *
 * This page works regardless of origin:
 *   - http://localhost:8081/sitelink/sso/callback
 *   - http://10.24.15.169:8081/sitelink/sso/callback
 *   - https://mlmt.mobifone.vn/sitelink/sso/callback
 *
 * Steps:
 *   1. Read ?code from URL
 *   2. Validate state (CSRF protection)
 *   3. Call POST /api/v1/auth/sso/callback { code, redirect_uri }
 *   4. Store returned JWT
 *   5. Redirect to dashboard
 */
import React, { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Spin, Alert, Button, Typography, Space } from 'antd'
import { ssoCallback, getMe, buildCallbackUrl } from '@/api/auth'
import { useAuthStore } from '@/store/auth'

type Status = 'loading' | 'error' | 'success'

export default function SsoCallbackPage() {
  const navigate          = useNavigate()
  const [params]          = useSearchParams()
  const setAuth           = useAuthStore((s) => s.setAuth)
  const [status, setStatus] = useState<Status>('loading')
  const [error,  setError]  = useState('')
  const [detail, setDetail] = useState('')

  useEffect(() => {
    const code         = params.get('code')
    const state        = params.get('state')
    const errorParam   = params.get('error')
    const errorDesc    = params.get('error_description')

    // Handle Keycloak error redirect (e.g. user cancelled login)
    if (errorParam) {
      setError(`SSO Error: ${errorParam}`)
      setDetail(errorDesc || '')
      setStatus('error')
      return
    }

    if (!code) {
      setError('Khong nhan duoc ma xac thuc tu SSO')
      setDetail('URL khong chua tham so "code"')
      setStatus('error')
      return
    }

    // CSRF state validation
    const savedState = sessionStorage.getItem('sso_state')
    sessionStorage.removeItem('sso_state')

    if (savedState && state && savedState !== state) {
      setError('State khong hop le (CSRF protection)')
      setDetail(`Expected: ${savedState}, Got: ${state}`)
      setStatus('error')
      return
    }

    // The redirect_uri MUST match exactly what was sent to Keycloak
    const redirectUri = buildCallbackUrl()

    ssoCallback(code, redirectUri)
      .then(async ({ access_token }) => {
        localStorage.setItem('sl_token', access_token)
        const me = await getMe()
        setAuth(me, access_token)
        setStatus('success')
        // Small delay so user sees success state briefly
        setTimeout(() => navigate('/', { replace: true }), 800)
      })
      .catch((e: any) => {
        const msg = e?.response?.data?.detail || e?.message || 'SSO callback that bai'
        setError('Dang nhap SSO that bai')
        setDetail(msg)
        setStatus('error')
      })
  }, [])

  if (status === 'loading') {
    return (
      <div style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexDirection: 'column',
        gap: 16,
        background: 'linear-gradient(135deg,#1a1a2e,#16213e,#0f3460)',
      }}>
        <Spin size="large" />
        <Typography.Text style={{ color: '#fff' }}>
          Dang xu ly dang nhap SSO...
        </Typography.Text>
        <Typography.Text style={{ color: 'rgba(255,255,255,0.5)', fontSize: 12 }}>
          {buildCallbackUrl()}
        </Typography.Text>
      </div>
    )
  }

  if (status === 'success') {
    return (
      <div style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexDirection: 'column',
        gap: 16,
        background: 'linear-gradient(135deg,#1a1a2e,#16213e,#0f3460)',
      }}>
        <Typography.Text style={{ color: '#52c41a', fontSize: 18 }}>
          ✓ Dang nhap thanh cong! Dang chuyen trang...
        </Typography.Text>
      </div>
    )
  }

  // Error state
  return (
    <div style={{
      minHeight: '100vh',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: 32,
      background: 'linear-gradient(135deg,#1a1a2e,#16213e,#0f3460)',
    }}>
      <div style={{ maxWidth: 520, width: '100%' }}>
        <Alert
          type="error"
          showIcon
          message={error}
          description={
            <Space direction="vertical" style={{ width: '100%' }}>
              {detail && (
                <Typography.Text
                  code
                  style={{ fontSize: 11, wordBreak: 'break-all' }}
                >
                  {detail}
                </Typography.Text>
              )}
              <Typography.Text type="secondary" style={{ fontSize: 11 }}>
                Callback URL: {buildCallbackUrl()}
              </Typography.Text>
            </Space>
          }
        />
        <div style={{ marginTop: 16, textAlign: 'center' }}>
          <Button
            type="primary"
            onClick={() => navigate('/login', { replace: true })}
          >
            Quay lai trang dang nhap
          </Button>
        </div>
      </div>
    </div>
  )
}
