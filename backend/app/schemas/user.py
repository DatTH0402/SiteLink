from typing import Optional
from pydantic import BaseModel
from app.models.user import UserRole, UserAuthProvider


class UserBase(BaseModel):
    email: str                          # changed from EmailStr to str
    username: str
    full_name: Optional[str] = None
    role: UserRole = UserRole.user
    is_active: bool = True


class UserCreate(UserBase):
    password: str


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    role: Optional[UserRole] = None
    is_active: Optional[bool] = None
    password: Optional[str] = None


class UserRead(UserBase):
    id: int
    auth_provider: UserAuthProvider

    class Config:
        from_attributes = True


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class TokenPayload(BaseModel):
    sub: Optional[str] = None
    role: Optional[str] = None