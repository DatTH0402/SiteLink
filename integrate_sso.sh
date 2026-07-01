#!/bin/bash
# integrate_sso.sh
# Fixes SSO integration for localhost:8081, 10.24.15.169:8081, and mlmt.mobifone.vn
# Usage: chmod +x integrate_sso.sh && ./integrate_sso.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "SiteLink SSO Integration Script"
echo "========================================"

# ── Step 1: Update backend/app/core/config.py ────────────────────────────────
echo "[1/6] Updating backend config..."

cat > backend/app/core/config.py << 'PYEOF'
from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    POSTGRES_USER: str = "sitelink"
    POSTGRES_PASSWORD: str = "sitelink_pass"
    POSTGRES_DB: str = "sitelink_db"
    POSTGRES_HOST: str = "postgres"
    POSTGRES_PORT: int = 5432

    SECRET_KEY: str = "change_me"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 480

    # SSO
    SSO_ENABLED: bool = True
    SSO_HOST: str = "https://auth-sso2fa.mobifone.vn"
    SSO_API_PORT: str = "8015"
    SSO_AUTH_PORT: str = "8080"
    SSO_REALM: str = "sso-mobifone"
    SSO_CLIENT_ID: str = "CLIENT-MLMT"
    SSO_CLIENT_SECRET: str = "gy2xyLo1hmRpd1Z61Hc3g7rTz51q5T4C"

    # SSO_REDIRECT_URI is now DYNAMIC — set per-request from the frontend.
    # This default is used only as fallback for sso/config endpoint.
    SSO_REDIRECT_URI: str = "http://localhost:8081/sitelink/sso/callback"

    @property
    def DATABASE_URL(self) -> str:
        return (
            f"postgresql://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    @property
    def SSO_AUTH_BASE(self) -> str:
        return f"{self.SSO_HOST}:{self.SSO_AUTH_PORT}"

    @property
    def SSO_API_BASE(self) -> str:
        return f"{self.SSO_HOST}:{self.SSO_API_PORT}"

    @property
    def SSO_LOGIN_URL(self) -> str:
        return (
            f"{self.SSO_AUTH_BASE}/oauth/realms/{self.SSO_REALM}"
            f"/protocol/openid-connect/auth"
        )

    @property
    def SSO_TOKEN_URL(self) -> str:
        """Standard Keycloak token endpoint — used for code exchange."""
        return (
            f"{self.SSO_AUTH_BASE}/oauth/realms/{self.SSO_REALM}"
            f"/protocol/openid-connect/token"
        )

    @property
    def SSO_LOGOUT_URL(self) -> str:
        return (
            f"{self.SSO_AUTH_BASE}/oauth/realms/{self.SSO_REALM}"
            f"/protocol/openid-connect/logout"
        )

    @property
    def SSO_USERINFO_URL(self) -> str:
        return (
            f"{self.SSO_AUTH_BASE}/oauth/realms/{self.SSO_REALM}"
            f"/protocol/openid-connect/userinfo"
        )

    class Config:
        env_file = ".env"


settings = Settings()
PYEOF

echo "    ✓ config.py updated"

# ── Step 2: Update backend/app/api/routes/auth.py ────────────────────────────
echo "[2/6] Updating backend auth routes..."

cat > backend/app/api/routes/auth.py << 'PYEOF'
"""
auth.py
-------
Handles both local login and MobiFone SSO (Keycloak) login.

Key design: redirect_uri is DYNAMIC — the frontend passes its own origin
so the same backend works for:
  - http://localhost:8081/sitelink/sso/callback
  - http://10.24.15.169:8081/sitelink/sso/callback
  - https://mlmt.mobifone.vn/sitelink/sso/callback

SSO Flow:
  1. Frontend calls GET /api/v1/auth/sso/login-url?redirect_uri=<its own callback URL>
     → backend builds and returns the Keycloak authorization URL
  2. Frontend redirects browser to Keycloak login page
  3. Keycloak authenticates user, redirects to redirect_uri?code=xxx
  4. Frontend (SsoCallbackPage) reads code from URL
  5. Frontend calls POST /api/v1/auth/sso/callback {code, redirect_uri}
     → backend exchanges code for token using STANDARD Keycloak token endpoint
     → upserts user in DB, returns our own JWT
  6. Frontend stores JWT and proceeds normally
"""
import base64
import json as _json
import secrets

import httpx

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.user import Token, UserRead
from app.services.auth import authenticate_user, get_or_create_sso_user
from app.core.security import create_access_token
from app.core.config import settings
from app.utils.deps import get_current_user
from app.models.user import User

router = APIRouter()


# ── Local login ───────────────────────────────────────────────────────────────

@router.post("/login", response_model=Token)
def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
):
    user = authenticate_user(db, form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
        )
    token = create_access_token({"sub": user.username, "role": user.role.value})
    return {"access_token": token, "token_type": "bearer"}


@router.get("/me", response_model=UserRead)
def me(current_user: User = Depends(get_current_user)):
    return current_user


# ── SSO helpers ───────────────────────────────────────────────────────────────

def _build_redirect_uri(request: Request, custom_uri: str | None) -> str:
    """
    Resolve redirect_uri:
    1. Use explicitly provided redirect_uri (from query param or body)
    2. Fall back to settings default
    """
    if custom_uri and custom_uri.strip():
        return custom_uri.strip()
    return settings.SSO_REDIRECT_URI


# ── SSO: step 1 – return authorization URL ───────────────────────────────────

@router.get("/sso/login-url")
def sso_login_url(
    request: Request,
    redirect_uri: str | None = None,
):
    """
    Returns the Keycloak authorization URL.
    Frontend passes its own redirect_uri so the callback goes back to the
    correct host (localhost, IP, or domain).

    Example:
      GET /api/v1/auth/sso/login-url?redirect_uri=http://localhost:8081/sitelink/sso/callback
    """
    if not settings.SSO_ENABLED:
        raise HTTPException(status_code=400, detail="SSO is not enabled")

    effective_redirect_uri = _build_redirect_uri(request, redirect_uri)
    state = secrets.token_urlsafe(16)

    url = (
        f"{settings.SSO_LOGIN_URL}"
        f"?client_id={settings.SSO_CLIENT_ID}"
        f"&scope=openid%20email%20profile"
        f"&response_type=code"
        f"&redirect_uri={effective_redirect_uri}"
        f"&state={state}"
    )
    return {
        "url": url,
        "state": state,
        "sso_enabled": settings.SSO_ENABLED,
        "redirect_uri": effective_redirect_uri,
    }


# ── SSO: step 2 – exchange code for token, return our JWT ────────────────────

@router.post("/sso/callback", response_model=Token)
async def sso_callback(
    payload: dict,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Receives {code: "...", redirect_uri: "..."} from frontend.

    IMPORTANT: redirect_uri must be EXACTLY the same URI that was used
    in step 1 (sso/login-url). Keycloak validates this.

    Uses the standard Keycloak token endpoint (port 8080), NOT the
    SSO API /code-to-token endpoint.
    """
    code = payload.get("code")
    if not code:
        raise HTTPException(status_code=400, detail="Missing authorization code")

    redirect_uri = _build_redirect_uri(request, payload.get("redirect_uri"))

    # ── Step 1: Exchange code for tokens via standard Keycloak endpoint ───
    token_url = settings.SSO_TOKEN_URL

    async with httpx.AsyncClient(verify=False, timeout=30) as client:
        token_resp = await client.post(
            token_url,
            data={
                "grant_type":    "authorization_code",
                "code":          code,
                "client_id":     settings.SSO_CLIENT_ID,
                "client_secret": settings.SSO_CLIENT_SECRET,
                "redirect_uri":  redirect_uri,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )

    if token_resp.status_code not in (200, 201):
        raise HTTPException(
            status_code=401,
            detail=f"SSO token exchange failed ({token_resp.status_code}): {token_resp.text[:300]}",
        )

    token_data = token_resp.json()
    access_token = token_data.get("access_token")
    id_token     = token_data.get("id_token")

    if not access_token:
        raise HTTPException(
            status_code=401,
            detail=f"No access_token in SSO response: {str(token_data)[:200]}",
        )

    # ── Step 2: Decode JWT to get user claims ─────────────────────────────
    try:
        parts = access_token.split(".")
        if len(parts) < 2:
            raise ValueError("Not a valid JWT")
        padding  = 4 - len(parts[1]) % 4
        padded   = parts[1] + ("=" * padding)
        jwt_payload = _json.loads(base64.urlsafe_b64decode(padded))

        user_id            = jwt_payload.get("sub", "")
        email_from_token   = jwt_payload.get("email", "")
        name_from_token    = jwt_payload.get("name", "")
        preferred_username = jwt_payload.get("preferred_username", "")
        realm_roles        = jwt_payload.get("realm_access", {}).get("roles", [])
    except Exception as exc:
        raise HTTPException(
            status_code=401,
            detail=f"Cannot decode SSO token: {exc}",
        )

    if not user_id:
        raise HTTPException(status_code=401, detail="No user_id (sub) in token")

    # ── Step 3: Try to get richer user info from userinfo endpoint ────────
    sso_data = {
        "sub":      user_id,
        "email":    email_from_token,
        "name":     name_from_token,
        "username": preferred_username or email_from_token,
        "roles":    realm_roles,
        "id_token": id_token,
    }

    try:
        async with httpx.AsyncClient(verify=False, timeout=10) as client:
            ui_resp = await client.get(
                settings.SSO_USERINFO_URL,
                headers={"Authorization": f"Bearer {access_token}"},
            )
        if ui_resp.status_code == 200:
            ui = ui_resp.json()
            if ui.get("email"):
                sso_data["email"] = ui["email"]
            if ui.get("name"):
                sso_data["name"] = ui["name"]
    except Exception:
        pass  # userinfo failure is non-fatal; JWT claims are sufficient

    # ── Step 4: Upsert user in local DB ──────────────────────────────────
    user = get_or_create_sso_user(db, sso_data)

    # ── Step 5: Return our own JWT ────────────────────────────────────────
    our_token = create_access_token({
        "sub":  user.username,
        "role": user.role.value,
    })
    return {"access_token": our_token, "token_type": "bearer"}


# ── SSO logout ────────────────────────────────────────────────────────────────

@router.post("/sso/logout")
async def sso_logout(payload: dict):
    """
    Calls Keycloak logout endpoint with id_token_hint.
    Frontend clears its local token regardless of SSO logout result.
    """
    id_token = payload.get("id_token")
    if not id_token:
        return {"message": "Local logout only (no id_token provided)"}

    try:
        async with httpx.AsyncClient(verify=False, timeout=10) as client:
            await client.post(
                settings.SSO_LOGOUT_URL,
                data={
                    "client_id":     settings.SSO_CLIENT_ID,
                    "client_secret": settings.SSO_CLIENT_SECRET,
                    "id_token_hint": id_token,
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
    except Exception:
        pass  # SSO logout failure must not block local logout

    return {"message": "Logged out"}


@router.get("/sso/config")
def sso_config():
    """Returns SSO configuration for the frontend."""
    return {
        "sso_enabled":   settings.SSO_ENABLED,
        "client_id":     settings.SSO_CLIENT_ID,
        "redirect_uri":  settings.SSO_REDIRECT_URI,  # default only
    }
PYEOF

echo "    ✓ auth.py updated"

# ── Step 3: Update frontend/src/api/auth.ts ───────────────────────────────────
echo "[3/6] Updating frontend auth API..."

cat > frontend/src/api/auth.ts << 'TSEOF'
import api from './client'
import type { User } from '@/types'

export const login = (username: string, password: string) => {
  const form = new URLSearchParams()
  form.append('username', username)
  form.append('password', password)
  return api
    .post<{ access_token: string; token_type: string }>(
      '/api/v1/auth/login',
      form,
      { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } },
    )
    .then((r) => r.data)
}

export const getMe = () =>
  api.get<User>('/api/v1/auth/me').then((r) => r.data)

/**
 * Build the callback URL dynamically from the current browser location.
 * Works for localhost:8081, 10.24.15.169:8081, mlmt.mobifone.vn, etc.
 */
export function buildCallbackUrl(): string {
  const { protocol, host } = window.location
  return `${protocol}//${host}/sitelink/sso/callback`
}

/**
 * Get Keycloak authorization URL.
 * Always passes the dynamic redirect_uri so the backend uses the correct host.
 */
export const getSsoLoginUrl = () => {
  const redirectUri = buildCallbackUrl()
  return api
    .get<{ url: string; state: string; sso_enabled: boolean; redirect_uri: string }>(
      `/api/v1/auth/sso/login-url?redirect_uri=${encodeURIComponent(redirectUri)}`
    )
    .then((r) => r.data)
}

/**
 * Exchange authorization code for our JWT.
 * MUST pass the same redirect_uri that was used to get the code.
 */
export const ssoCallback = (code: string, redirectUri?: string) =>
  api
    .post<{ access_token: string; token_type: string }>(
      '/api/v1/auth/sso/callback',
      { code, redirect_uri: redirectUri ?? buildCallbackUrl() }
    )
    .then((r) => r.data)

/** Logout from SSO server */
export const ssoLogout = (id_token?: string) =>
  api.post('/api/v1/auth/sso/logout', { id_token }).then((r) => r.data)

/** Get SSO config */
export const getSsoConfig = () =>
  api
    .get<{ sso_enabled: boolean; client_id: string; redirect_uri: string }>(
      '/api/v1/auth/sso/config'
    )
    .then((r) => r.data)
TSEOF

echo "    ✓ auth.ts updated"

# ── Step 4: Update frontend/src/pages/auth/LoginPage.tsx ─────────────────────
echo "[4/6] Updating LoginPage..."

cat > frontend/src/pages/auth/LoginPage.tsx << 'TSXEOF'
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
TSXEOF

echo "    ✓ LoginPage.tsx updated"

# ── Step 5: Update frontend/src/pages/auth/SsoCallbackPage.tsx ───────────────
echo "[5/6] Updating SsoCallbackPage..."

cat > frontend/src/pages/auth/SsoCallbackPage.tsx << 'TSXEOF'
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
TSXEOF

echo "    ✓ SsoCallbackPage.tsx updated"

# ── Step 6: Update .env ───────────────────────────────────────────────────────
echo "[6/6] Updating .env..."

# Back up original
cp .env .env.bak.$(date +%Y%m%d_%H%M%S)

cat > .env << 'ENVEOF'
# PostgreSQL
POSTGRES_USER=sitelink
POSTGRES_PASSWORD=sitelink_pass
POSTGRES_DB=sitelink_db
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# Backend
SECRET_KEY=change_this_to_a_very_long_random_secret_key_minimum_32_chars
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=480

# Frontend (Vite build-time)
VITE_API_BASE_URL=http://localhost:8081/api

# SSO Configuration
SSO_ENABLED=true
SSO_HOST=https://auth-sso2fa.mobifone.vn
SSO_API_PORT=8015
SSO_AUTH_PORT=8080
SSO_REALM=sso-mobifone
SSO_CLIENT_ID=CLIENT-MLMT
SSO_CLIENT_SECRET=gy2xyLo1hmRpd1Z61Hc3g7rTz51q5T4C

# SSO_REDIRECT_URI is now dynamic (set per-request from frontend).
# This value is only used as a fallback default.
# Keycloak must have ALL these URIs registered as valid redirect URIs:
#   http://localhost:8081/sitelink/sso/callback
#   http://10.24.15.169:8081/sitelink/sso/callback
#   https://mlmt.mobifone.vn/sitelink/sso/callback
SSO_REDIRECT_URI=http://localhost:8081/sitelink/sso/callback
ENVEOF

echo "    ✓ .env updated"

# ── Rebuild and restart ───────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "Rebuilding and restarting containers..."
echo "========================================"
sudo docker compose down
sudo docker compose up -d --build

echo ""
echo "========================================"
echo "IMPORTANT: Keycloak Redirect URI Setup"
echo "========================================"
echo ""
echo "You MUST register these redirect URIs in Keycloak CLIENT-MLMT:"
echo ""
echo "  1. http://localhost:8081/sitelink/sso/callback"
echo "  2. http://10.24.15.169:8081/sitelink/sso/callback"
echo "  3. https://mlmt.mobifone.vn/sitelink/sso/callback"
echo ""
echo "In Keycloak Admin Console:"
echo "  Clients → CLIENT-MLMT → Settings → Valid Redirect URIs"
echo "  Add all 3 URIs above"
echo ""
echo "========================================"
echo "Test URLs"
echo "========================================"
echo ""
echo "  Local:   http://localhost:8081/sitelink/"
echo "  IP:      http://10.24.15.169:8081/sitelink/"
echo "  Domain:  https://mlmt.mobifone.vn/sitelink/  (after domain setup)"
echo ""
echo "SSO Login flow:"
echo "  1. Click 'Dang nhap bang SSO MobiFone'"
echo "  2. Login with admin_mlmt@mobifone.vn"
echo "  3. Keycloak redirects back to your current host's callback"
echo "  4. You are logged in as SSO user"
echo ""
echo "========================================"
echo "Done!"
echo "========================================"