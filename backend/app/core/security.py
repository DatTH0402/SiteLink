"""
security.py
-----------
Password hashing uses the `bcrypt` library directly.
passlib 1.7.4 is NOT used because it is incompatible with bcrypt >= 4.0
(passlib references bcrypt.__about__.__version__ which no longer exists,
causing verify_password to silently return False).
"""
from datetime import datetime, timedelta, timezone
from typing import Optional

import bcrypt
from jose import JWTError, jwt

from app.core.config import settings


# ── Password hashing ──────────────────────────────────────────────────────────

def get_password_hash(password: str) -> str:
    """Return a bcrypt hash of *password*."""
    pwd_bytes = password.encode("utf-8")
    salt      = bcrypt.gensalt()
    return bcrypt.hashpw(pwd_bytes, salt).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    """
    Return True if *plain* matches *hashed*.
    Handles both:
      - hashes created by this module (bcrypt direct)
      - hashes created by the old passlib code (also bcrypt, same format)
    """
    try:
        return bcrypt.checkpw(
            plain.encode("utf-8"),
            hashed.encode("utf-8"),
        )
    except Exception:
        return False


# ── JWT ───────────────────────────────────────────────────────────────────────

def create_access_token(
    data: dict,
    expires_delta: Optional[timedelta] = None,
) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta
        or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode.update({"exp": expire})
    return jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )


def decode_access_token(token: str) -> Optional[dict]:
    try:
        return jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
    except JWTError:
        return None
