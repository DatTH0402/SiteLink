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
