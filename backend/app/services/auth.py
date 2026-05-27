from typing import Optional
from sqlalchemy.orm import Session

from app.models.user import User, UserRole, UserAuthProvider
from app.core.security import verify_password, get_password_hash


def authenticate_user(db: Session, username: str, password: str) -> Optional[User]:
    user = db.query(User).filter(
        (User.username == username) | (User.email == username)
    ).first()
    if not user:
        return None
    if user.auth_provider != UserAuthProvider.local:
        return None
    if not verify_password(password, user.hashed_password or ""):
        return None
    return user


def get_or_create_sso_user(db: Session, sso_data: dict) -> User:
    """Called after SSO token validation. sso_data keys: sub, email, name"""
    user = db.query(User).filter(User.sso_subject == sso_data["sub"]).first()
    if not user:
        user = User(
            email=sso_data.get("email", ""),
            username=sso_data.get("email", sso_data["sub"]),
            full_name=sso_data.get("name"),
            role=UserRole.user,
            auth_provider=UserAuthProvider.sso,
            sso_subject=sso_data["sub"],
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    return user


def create_user(
    db: Session,
    email: str,
    username: str,
    password: str,
    full_name: str = "",
    role: UserRole = UserRole.user,
) -> User:
    user = User(
        email=email,
        username=username,
        full_name=full_name,
        hashed_password=get_password_hash(password),
        role=role,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
