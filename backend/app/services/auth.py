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
    """
    Called after SSO token validation.
    sso_data keys: sub, email, name, username, roles, id_token
    
    Logic:
    1. Look up by sso_subject (sub)
    2. If not found, look up by email (in case user was pre-created locally)
    3. If still not found, create new SSO user
    4. Update user info on every login
    """
    sub   = sso_data.get("sub", "")
    email = sso_data.get("email", "")
    name  = sso_data.get("name", "")
    roles = sso_data.get("roles", [])

    # Determine role: if SSO user has 'admin' realm role → admin
    role = UserRole.admin if "admin" in roles else UserRole.user

    # 1. Find by SSO subject
    user = db.query(User).filter(User.sso_subject == sub).first()

    # 2. Find by email (pre-created local account)
    if not user and email:
        user = db.query(User).filter(User.email == email).first()

    if user:
        # Update info on every login
        user.full_name    = name or user.full_name
        user.sso_subject  = sub
        user.auth_provider = UserAuthProvider.sso
        # Only update role if SSO provides one
        if roles:
            user.role = role
        db.commit()
        db.refresh(user)
        return user

    # 3. Create new user
    username = sso_data.get("username") or email or sub
    # Ensure username uniqueness
    existing_username = db.query(User).filter(User.username == username).first()
    if existing_username:
        username = email  # fall back to email as username

    user = User(
        email=email or f"{sub}@sso.local",
        username=username,
        full_name=name,
        role=role,
        auth_provider=UserAuthProvider.sso,
        sso_subject=sub,
        hashed_password=None,
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
