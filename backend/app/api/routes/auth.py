from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.user import Token, UserRead
from app.services.auth import authenticate_user
from app.core.security import create_access_token
from app.utils.deps import get_current_user
from app.models.user import User

router = APIRouter()


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


@router.get("/sso/login")
def sso_login():
    """Future: redirect to SSO provider."""
    return {"message": "SSO not yet configured. Use /auth/login with local credentials."}


@router.post("/sso/callback")
def sso_callback():
    """Future: handle SSO authorization code callback."""
    return {"message": "SSO callback placeholder"}
