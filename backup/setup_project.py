#!/usr/bin/env python3
"""
SiteLink Project Setup Script
Full path: /home/mlmt/work/src/SiteLink/setup_project.py
Run: python3 setup_project.py
"""

import os

BASE_DIR = "/home/mlmt/work/src/SiteLink"


def mkdir(path):
    os.makedirs(path, exist_ok=True)
    print(f"  [DIR]  {path}")


def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  [FILE] {path}")


def setup():
    print("=" * 60)
    print("  SiteLink Project Setup")
    print("=" * 60)

    # ------------------------------------------------------------------ #
    #  DIRECTORY TREE
    # ------------------------------------------------------------------ #
    dirs = [
        f"{BASE_DIR}/backend/app/api/routes",
        f"{BASE_DIR}/backend/app/core",
        f"{BASE_DIR}/backend/app/db",
        f"{BASE_DIR}/backend/app/models",
        f"{BASE_DIR}/backend/app/schemas",
        f"{BASE_DIR}/backend/app/services",
        f"{BASE_DIR}/backend/app/utils",
        f"{BASE_DIR}/frontend/src/api",
        f"{BASE_DIR}/frontend/src/components/common",
        f"{BASE_DIR}/frontend/src/components/layout",
        f"{BASE_DIR}/frontend/src/pages/auth",
        f"{BASE_DIR}/frontend/src/pages/dashboard",
        f"{BASE_DIR}/frontend/src/pages/sites",
        f"{BASE_DIR}/frontend/src/pages/cells",
        f"{BASE_DIR}/frontend/src/pages/admin",
        f"{BASE_DIR}/frontend/src/pages/dropdowns",
        f"{BASE_DIR}/frontend/src/store",
        f"{BASE_DIR}/frontend/src/types",
        f"{BASE_DIR}/frontend/src/utils",
        f"{BASE_DIR}/nginx",
        f"{BASE_DIR}/postgres/init",
    ]
    for d in dirs:
        mkdir(d)

    # ================================================================== #
    #  ROOT FILES
    # ================================================================== #

    write_file(f"{BASE_DIR}/.env", """\
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
VITE_API_BASE_URL=http://localhost/api

# SSO (future - leave blank for now)
SSO_CLIENT_ID=
SSO_CLIENT_SECRET=
SSO_AUTHORITY=
""")

    write_file(f"{BASE_DIR}/docker-compose.yml", """\
version: "3.9"

services:
  postgres:
    image: postgres:15-alpine
    container_name: sitelink_postgres
    restart: unless-stopped
    env_file: .env
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgres/init:/docker-entrypoint-initdb.d
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: sitelink_backend
    restart: unless-stopped
    env_file: .env
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./backend:/app
    ports:
      - "8000:8000"
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: sitelink_frontend
    restart: unless-stopped
    depends_on:
      - backend
    ports:
      - "5173:80"

  nginx:
    image: nginx:alpine
    container_name: sitelink_nginx
    restart: unless-stopped
    depends_on:
      - backend
      - frontend
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro

volumes:
  postgres_data:
""")

    # ================================================================== #
    #  NGINX
    # ================================================================== #
    write_file(f"{BASE_DIR}/nginx/nginx.conf", """\
worker_processes 1;
events { worker_connections 1024; }

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    client_max_body_size 50M;

    upstream backend  { server backend:8000; }
    upstream frontend { server frontend:80; }

    server {
        listen 80;
        server_name _;

        location /api/ {
            proxy_pass         http://backend/;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_read_timeout 300s;
        }

        location / {
            proxy_pass       http://frontend;
            proxy_set_header Host $host;
        }
    }
}
""")

    # ================================================================== #
    #  BACKEND
    # ================================================================== #

    write_file(f"{BASE_DIR}/backend/Dockerfile", """\
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libpq-dev && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
""")

    write_file(f"{BASE_DIR}/backend/requirements.txt", """\
fastapi==0.111.0
uvicorn[standard]==0.29.0
sqlalchemy==2.0.30
alembic==1.13.1
psycopg2-binary==2.9.9
pydantic==2.7.1
pydantic-settings==2.2.1
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.9
pandas==2.2.2
openpyxl==3.1.2
httpx==0.27.0
python-dotenv==1.0.1
""")

    write_file(f"{BASE_DIR}/backend/app/__init__.py", "")

    # ── app/core ──────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/backend/app/core/__init__.py", "")

    write_file(f"{BASE_DIR}/backend/app/core/config.py", """\
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    POSTGRES_USER: str = "sitelink"
    POSTGRES_PASSWORD: str = "sitelink_pass"
    POSTGRES_DB: str = "sitelink_db"
    POSTGRES_HOST: str = "postgres"
    POSTGRES_PORT: int = 5432

    SECRET_KEY: str = "change_me"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 480

    # SSO placeholders
    SSO_CLIENT_ID: str = ""
    SSO_CLIENT_SECRET: str = ""
    SSO_AUTHORITY: str = ""

    @property
    def DATABASE_URL(self) -> str:
        return (
            f"postgresql://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    class Config:
        env_file = ".env"


settings = Settings()
""")

    write_file(f"{BASE_DIR}/backend/app/core/security.py", """\
from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_access_token(token: str) -> Optional[dict]:
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        return None
""")

    # ── app/db ────────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/backend/app/db/__init__.py", "")

    write_file(f"{BASE_DIR}/backend/app/db/session.py", """\
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings

engine = create_engine(settings.DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
""")

    write_file(f"{BASE_DIR}/backend/app/db/base.py", """\
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


# Import all models so SQLAlchemy registers them
from app.models import (  # noqa
    user, site, cell_3g, cell_4g, cell_5g,
    dropdown, audit_log
)
""")

    # ── app/models ────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/backend/app/models/__init__.py", "")

    write_file(f"{BASE_DIR}/backend/app/models/user.py", """\
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Enum as PgEnum
import enum

from app.db.base import Base


class UserRole(str, enum.Enum):
    admin = "admin"
    user = "user"


class UserAuthProvider(str, enum.Enum):
    local = "local"
    sso = "sso"


class User(Base):
    __tablename__ = "users"

    id               = Column(Integer, primary_key=True, index=True)
    email            = Column(String(255), unique=True, index=True, nullable=False)
    username         = Column(String(100), unique=True, index=True, nullable=False)
    full_name        = Column(String(255))
    hashed_password  = Column(String(255), nullable=True)
    role             = Column(PgEnum(UserRole), default=UserRole.user, nullable=False)
    is_active        = Column(Boolean, default=True)
    auth_provider    = Column(PgEnum(UserAuthProvider), default=UserAuthProvider.local)
    sso_subject      = Column(String(255), nullable=True, unique=True)
    created_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc))
    updated_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc),
                              onupdate=lambda: datetime.now(timezone.utc))
""")

    write_file(f"{BASE_DIR}/backend/app/models/site.py", """\
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.orm import relationship

from app.db.base import Base


class Site(Base):
    __tablename__ = "sites"

    id                   = Column(Integer, primary_key=True, index=True)
    mien                 = Column(String(10), nullable=False)
    tinh                 = Column(String(100), nullable=False)
    phuong_xa            = Column(String(150))
    site_name_cu         = Column(String(100))
    site_name            = Column(String(100), nullable=False, unique=True, index=True)
    site_vip             = Column(String(10))
    lat                  = Column(Float, nullable=False)
    long                 = Column(Float, nullable=False)
    tram_2g              = Column(Boolean, default=False)
    tram_3g              = Column(Boolean, default=False)
    tram_4g              = Column(Boolean, default=False)
    tram_5g              = Column(Boolean, default=False)
    repeater             = Column(Boolean, default=False)
    booster              = Column(Boolean, default=False)
    node_truyen_dan_only = Column(Boolean, default=False)
    phan_loai_tram       = Column(String(100))
    tram_phu_song_tsca   = Column(String(50))
    moran_3g             = Column(String(50))
    moran_4g             = Column(String(50))
    moran_5g             = Column(String(50))
    ma_ptm               = Column(String(100), nullable=False)
    do_cao_dinh_cot_anten = Column(Float)
    do_cao_cot_anten     = Column(Float)
    dia_chi              = Column(Text)
    ghi_chu              = Column(Text)
    created_at           = Column(DateTime(timezone=True),
                                  default=lambda: datetime.now(timezone.utc))
    updated_at           = Column(DateTime(timezone=True),
                                  default=lambda: datetime.now(timezone.utc),
                                  onupdate=lambda: datetime.now(timezone.utc))
    created_by           = Column(Integer, ForeignKey("users.id"), nullable=True)

    cells_3g = relationship("Cell3G", back_populates="site", cascade="all, delete-orphan")
    cells_4g = relationship("Cell4G", back_populates="site", cascade="all, delete-orphan")
    cells_5g = relationship("Cell5G", back_populates="site", cascade="all, delete-orphan")
""")

    write_file(f"{BASE_DIR}/backend/app/models/cell_3g.py", """\
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship

from app.db.base import Base


class Cell3G(Base):
    __tablename__ = "cells_3g"

    id            = Column(Integer, primary_key=True, index=True)
    site_id       = Column(Integer, ForeignKey("sites.id", ondelete="CASCADE"),
                           nullable=False, index=True)
    mien          = Column(String(10))
    tinh          = Column(String(100))
    phuong_xa     = Column(String(150))
    site_name     = Column(String(100), nullable=False, index=True)
    cell_name     = Column(String(100), nullable=False, index=True)
    cell_vip      = Column(String(10))
    moran         = Column(String(50))
    lat           = Column(Float)
    long          = Column(Float)
    vung_phu_song = Column(String(20))
    vendor        = Column(String(50))
    do_cao_anten  = Column(Float)
    azimuth       = Column(Float)
    m_tilt        = Column(Float)
    e_tilt        = Column(Float)
    total_tilt    = Column(Float)
    loai_anten    = Column(String(200))
    chung_anten   = Column(String(100))
    baseband      = Column(String(100))
    rf            = Column(String(100))
    cell_id       = Column(String(50))
    arfcn         = Column(String(50))
    psc           = Column(String(50))
    mimo          = Column(String(20))
    created_at    = Column(DateTime(timezone=True),
                           default=lambda: datetime.now(timezone.utc))
    updated_at    = Column(DateTime(timezone=True),
                           default=lambda: datetime.now(timezone.utc),
                           onupdate=lambda: datetime.now(timezone.utc))
    created_by    = Column(Integer, ForeignKey("users.id"), nullable=True)

    site = relationship("Site", back_populates="cells_3g")
""")

    write_file(f"{BASE_DIR}/backend/app/models/cell_4g.py", """\
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship

from app.db.base import Base


class Cell4G(Base):
    __tablename__ = "cells_4g"

    id               = Column(Integer, primary_key=True, index=True)
    site_id          = Column(Integer, ForeignKey("sites.id", ondelete="CASCADE"),
                              nullable=False, index=True)
    mien             = Column(String(10))
    tinh             = Column(String(100))
    phuong_xa        = Column(String(150))
    site_name        = Column(String(100), nullable=False, index=True)
    cell_name        = Column(String(100), nullable=False, index=True)
    cell_vip         = Column(String(10))
    moran            = Column(String(50))
    lat              = Column(Float)
    long             = Column(Float)
    vung_phu_song    = Column(String(20))
    vendor           = Column(String(50))
    do_cao_anten     = Column(Float)
    azimuth          = Column(Float)
    m_tilt           = Column(Float)
    e_tilt           = Column(Float)
    total_tilt       = Column(Float)
    loai_anten       = Column(String(200))
    chung_anten      = Column(String(100))
    baseband         = Column(String(100))
    rf               = Column(String(100))
    cell_id          = Column(String(50))
    earfcn           = Column(String(50))
    pci              = Column(String(50))
    root_sequence_id = Column(String(50))
    mimo             = Column(String(20))
    created_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc))
    updated_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc),
                              onupdate=lambda: datetime.now(timezone.utc))
    created_by       = Column(Integer, ForeignKey("users.id"), nullable=True)

    site = relationship("Site", back_populates="cells_4g")
""")

    write_file(f"{BASE_DIR}/backend/app/models/cell_5g.py", """\
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship

from app.db.base import Base


class Cell5G(Base):
    __tablename__ = "cells_5g"

    id               = Column(Integer, primary_key=True, index=True)
    site_id          = Column(Integer, ForeignKey("sites.id", ondelete="CASCADE"),
                              nullable=False, index=True)
    mien             = Column(String(10))
    tinh             = Column(String(100))
    phuong_xa        = Column(String(150))
    site_name        = Column(String(100), nullable=False, index=True)
    cell_name        = Column(String(100), nullable=False, index=True)
    cell_vip         = Column(String(10))
    moran            = Column(String(50))
    lat              = Column(Float)
    long             = Column(Float)
    vung_phu_song    = Column(String(20))
    vendor           = Column(String(50))
    do_cao_anten     = Column(Float)
    azimuth          = Column(Float)
    m_tilt           = Column(Float)
    e_tilt           = Column(Float)
    total_tilt       = Column(Float)
    loai_anten       = Column(String(200))
    baseband         = Column(String(100))
    rf               = Column(String(100))
    cell_id          = Column(String(50))
    nr_arfcn         = Column(String(50))
    pci              = Column(String(50))
    root_sequence_id = Column(String(50))
    mimo             = Column(String(20))
    created_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc))
    updated_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc),
                              onupdate=lambda: datetime.now(timezone.utc))
    created_by       = Column(Integer, ForeignKey("users.id"), nullable=True)

    site = relationship("Site", back_populates="cells_5g")
""")

    write_file(f"{BASE_DIR}/backend/app/models/dropdown.py", """\
from sqlalchemy import Column, Integer, String
from app.db.base import Base


class DropdownTinhXaPhuong(Base):
    __tablename__ = "dropdown_tinh_xa_phuong"
    id            = Column(Integer, primary_key=True)
    stt           = Column(Integer)
    mien          = Column(String(10))
    ten_tinh      = Column(String(100))
    ten_phuong_xa = Column(String(150))
    ma_tinh       = Column(String(20))
    ma_phuong_xa  = Column(String(20))
    ky_tu_1_6     = Column(String(10))


class DropdownAntenna(Base):
    __tablename__ = "dropdown_antenna"
    id             = Column(Integer, primary_key=True)
    name           = Column(String(300), unique=True)
    no_of_ports    = Column(Integer)
    band           = Column(String(100))
    no_of_beam     = Column(Integer)
    horizontal_bw  = Column(String(50))
    vertical_bw    = Column(String(50))
    gain           = Column(String(50))
    etilt          = Column(String(50))
    h              = Column(String(50))
    w              = Column(String(50))
    d              = Column(String(50))
    weight         = Column(String(50))
    connector_type = Column(String(100))


class DropdownVendor(Base):
    __tablename__ = "dropdown_vendor"
    id        = Column(Integer, primary_key=True)
    vendor_2g = Column(String(50))
    vendor_3g = Column(String(50))
    vendor_4g = Column(String(50))
    vendor_5g = Column(String(50))


class DropdownGeneral(Base):
    __tablename__ = "dropdown_general"
    id       = Column(Integer, primary_key=True)
    category = Column(String(100), nullable=False, index=True)
    value    = Column(String(200), nullable=False)
    label    = Column(String(200))
""")

    write_file(f"{BASE_DIR}/backend/app/models/audit_log.py", """\
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, DateTime, Text, ForeignKey

from app.db.base import Base


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id         = Column(Integer, primary_key=True, index=True)
    user_id    = Column(Integer, ForeignKey("users.id"), nullable=True)
    username   = Column(String(100))
    action     = Column(String(20))
    table_name = Column(String(100))
    record_id  = Column(Integer)
    old_value  = Column(Text)
    new_value  = Column(Text)
    timestamp  = Column(DateTime(timezone=True),
                        default=lambda: datetime.now(timezone.utc))
""")

    # ── app/schemas ───────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/backend/app/schemas/__init__.py", "")

    write_file(f"{BASE_DIR}/backend/app/schemas/user.py", """\
from typing import Optional
from pydantic import BaseModel, EmailStr
from app.models.user import UserRole, UserAuthProvider


class UserBase(BaseModel):
    email: EmailStr
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
""")

    write_file(f"{BASE_DIR}/backend/app/schemas/site.py", """\
from typing import Optional
from pydantic import BaseModel


class SiteBase(BaseModel):
    mien: str
    tinh: str
    phuong_xa: Optional[str] = None
    site_name_cu: Optional[str] = None
    site_name: str
    site_vip: Optional[str] = None
    lat: float
    long: float
    tram_2g: bool = False
    tram_3g: bool = False
    tram_4g: bool = False
    tram_5g: bool = False
    repeater: bool = False
    booster: bool = False
    node_truyen_dan_only: bool = False
    phan_loai_tram: Optional[str] = None
    tram_phu_song_tsca: Optional[str] = None
    moran_3g: Optional[str] = None
    moran_4g: Optional[str] = None
    moran_5g: Optional[str] = None
    ma_ptm: str
    do_cao_dinh_cot_anten: Optional[float] = None
    do_cao_cot_anten: Optional[float] = None
    dia_chi: Optional[str] = None
    ghi_chu: Optional[str] = None


class SiteCreate(SiteBase):
    pass


class SiteUpdate(BaseModel):
    mien: Optional[str] = None
    tinh: Optional[str] = None
    phuong_xa: Optional[str] = None
    site_name_cu: Optional[str] = None
    site_name: Optional[str] = None
    site_vip: Optional[str] = None
    lat: Optional[float] = None
    long: Optional[float] = None
    tram_2g: Optional[bool] = None
    tram_3g: Optional[bool] = None
    tram_4g: Optional[bool] = None
    tram_5g: Optional[bool] = None
    repeater: Optional[bool] = None
    booster: Optional[bool] = None
    node_truyen_dan_only: Optional[bool] = None
    phan_loai_tram: Optional[str] = None
    tram_phu_song_tsca: Optional[str] = None
    moran_3g: Optional[str] = None
    moran_4g: Optional[str] = None
    moran_5g: Optional[str] = None
    ma_ptm: Optional[str] = None
    do_cao_dinh_cot_anten: Optional[float] = None
    do_cao_cot_anten: Optional[float] = None
    dia_chi: Optional[str] = None
    ghi_chu: Optional[str] = None


class SiteRead(SiteBase):
    id: int

    class Config:
        from_attributes = True
""")

    write_file(f"{BASE_DIR}/backend/app/schemas/cell.py", """\
from typing import Optional
from pydantic import BaseModel


class CellBase(BaseModel):
    site_id: int
    mien: Optional[str] = None
    tinh: Optional[str] = None
    phuong_xa: Optional[str] = None
    site_name: str
    cell_name: str
    cell_vip: Optional[str] = None
    moran: Optional[str] = None
    lat: Optional[float] = None
    long: Optional[float] = None
    vung_phu_song: Optional[str] = None
    vendor: Optional[str] = None
    do_cao_anten: Optional[float] = None
    azimuth: Optional[float] = None
    m_tilt: Optional[float] = None
    e_tilt: Optional[float] = None
    total_tilt: Optional[float] = None
    loai_anten: Optional[str] = None
    baseband: Optional[str] = None
    rf: Optional[str] = None
    cell_id: Optional[str] = None
    mimo: Optional[str] = None


# ---------- 3G ----------
class Cell3GBase(CellBase):
    chung_anten: Optional[str] = None
    arfcn: Optional[str] = None
    psc: Optional[str] = None


class Cell3GCreate(Cell3GBase):
    pass


class Cell3GUpdate(BaseModel):
    cell_vip: Optional[str] = None
    moran: Optional[str] = None
    lat: Optional[float] = None
    long: Optional[float] = None
    vung_phu_song: Optional[str] = None
    vendor: Optional[str] = None
    do_cao_anten: Optional[float] = None
    azimuth: Optional[float] = None
    m_tilt: Optional[float] = None
    e_tilt: Optional[float] = None
    total_tilt: Optional[float] = None
    loai_anten: Optional[str] = None
    chung_anten: Optional[str] = None
    baseband: Optional[str] = None
    rf: Optional[str] = None
    cell_id: Optional[str] = None
    arfcn: Optional[str] = None
    psc: Optional[str] = None
    mimo: Optional[str] = None


class Cell3GRead(Cell3GBase):
    id: int

    class Config:
        from_attributes = True


# ---------- 4G ----------
class Cell4GBase(CellBase):
    chung_anten: Optional[str] = None
    earfcn: Optional[str] = None
    pci: Optional[str] = None
    root_sequence_id: Optional[str] = None


class Cell4GCreate(Cell4GBase):
    pass


class Cell4GUpdate(BaseModel):
    cell_vip: Optional[str] = None
    moran: Optional[str] = None
    lat: Optional[float] = None
    long: Optional[float] = None
    vung_phu_song: Optional[str] = None
    vendor: Optional[str] = None
    do_cao_anten: Optional[float] = None
    azimuth: Optional[float] = None
    m_tilt: Optional[float] = None
    e_tilt: Optional[float] = None
    total_tilt: Optional[float] = None
    loai_anten: Optional[str] = None
    chung_anten: Optional[str] = None
    baseband: Optional[str] = None
    rf: Optional[str] = None
    cell_id: Optional[str] = None
    earfcn: Optional[str] = None
    pci: Optional[str] = None
    root_sequence_id: Optional[str] = None
    mimo: Optional[str] = None


class Cell4GRead(Cell4GBase):
    id: int

    class Config:
        from_attributes = True


# ---------- 5G ----------
class Cell5GBase(CellBase):
    nr_arfcn: Optional[str] = None
    pci: Optional[str] = None
    root_sequence_id: Optional[str] = None


class Cell5GCreate(Cell5GBase):
    pass


class Cell5GUpdate(BaseModel):
    cell_vip: Optional[str] = None
    moran: Optional[str] = None
    lat: Optional[float] = None
    long: Optional[float] = None
    vung_phu_song: Optional[str] = None
    vendor: Optional[str] = None
    do_cao_anten: Optional[float] = None
    azimuth: Optional[float] = None
    m_tilt: Optional[float] = None
    e_tilt: Optional[float] = None
    total_tilt: Optional[float] = None
    loai_anten: Optional[str] = None
    baseband: Optional[str] = None
    rf: Optional[str] = None
    cell_id: Optional[str] = None
    nr_arfcn: Optional[str] = None
    pci: Optional[str] = None
    root_sequence_id: Optional[str] = None
    mimo: Optional[str] = None


class Cell5GRead(Cell5GBase):
    id: int

    class Config:
        from_attributes = True
""")

    # ── app/services ──────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/backend/app/services/__init__.py", "")

    write_file(f"{BASE_DIR}/backend/app/services/auth.py", """\
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
    \"\"\"Called after SSO token validation. sso_data keys: sub, email, name\"\"\"
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
""")

    write_file(f"{BASE_DIR}/backend/app/services/import_excel.py", """\
import io
from typing import List, Dict, Any

import pandas as pd


def parse_site_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    records = []
    for _, row in df.iterrows():
        def f(col):
            v = row.get(col)
            return None if v is None or str(v).strip() == "" else v

        records.append({
            "mien":         f("Mien") or f("Mien"),
            "tinh":         f("Tinh"),
            "phuong_xa":    f("Phuong xa"),
            "site_name_cu": f("Site name (cu)"),
            "site_name":    f("Site name"),
            "site_vip":     f("Site VIP"),
            "lat":          float(f("Lat")) if f("Lat") else None,
            "long":         float(f("Long")) if f("Long") else None,
            "tram_2g":      str(f("Tram 2G")).strip().lower() == "x",
            "tram_3g":      str(f("Tram 3G")).strip().lower() == "x",
            "tram_4g":      str(f("Tram 4G")).strip().lower() == "x",
            "tram_5g":      str(f("Tram 5G")).strip().lower() == "x",
            "repeater":     str(f("Repeater")).strip().lower() == "x",
            "booster":      str(f("Booster")).strip().lower() == "x",
            "node_truyen_dan_only": str(f("Node truyen dan only")).strip().lower() == "x",
            "phan_loai_tram":   f("Phan loai tram"),
            "tram_phu_song_tsca": f("Tram phu song TSCA"),
            "moran_3g":     f("MORAN 3G"),
            "moran_4g":     f("MORAN 4G"),
            "moran_5g":     f("MORAN 5G"),
            "ma_ptm":       f("Ma PTM") or "",
            "do_cao_dinh_cot_anten": float(f("Do cao dinh cot anten")) if f("Do cao dinh cot anten") else None,
            "do_cao_cot_anten":      float(f("Do cao cot anten")) if f("Do cao cot anten") else None,
            "dia_chi":      f("Dia chi"),
            "ghi_chu":      f("Ghi chu"),
        })
    return records


def _cell_common(row) -> Dict[str, Any]:
    def f(col):
        v = row.get(col)
        return None if v is None or str(v).strip() == "" else v

    return {
        "mien":         f("Mien"),
        "tinh":         f("Tinh"),
        "phuong_xa":    f("Phuong xa"),
        "site_name":    f("Site Name") or f("Site name") or "",
        "cell_name":    f("Cell Name") or f("Cell name") or "",
        "cell_vip":     f("Cell VIP"),
        "moran":        f("MORAN"),
        "lat":          float(f("Lat")) if f("Lat") else None,
        "long":         float(f("Long")) if f("Long") else None,
        "vung_phu_song": f("Vung phu song"),
        "vendor":       f("Vendor"),
        "do_cao_anten": float(f("Do cao anten")) if f("Do cao anten") else None,
        "azimuth":      float(f("Azimuth")) if f("Azimuth") else None,
        "m_tilt":       float(f("M-tilt")) if f("M-tilt") else None,
        "e_tilt":       float(f("E-Tilt")) if f("E-Tilt") else None,
        "total_tilt":   float(f("Total Tilt")) if f("Total Tilt") else None,
        "loai_anten":   f("Loai Anten"),
        "baseband":     f("Baseband"),
        "rf":           f("RF"),
        "cell_id":      f("Cell ID"),
        "mimo":         f("MIMO"),
    }


def parse_cell3g_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    records = []
    for _, row in df.iterrows():
        def f(col):
            v = row.get(col)
            return None if v is None or str(v).strip() == "" else v
        rec = _cell_common(row)
        rec.update({
            "chung_anten": f("Chung anten"),
            "arfcn":       f("ARFCN"),
            "psc":         f("PSC"),
        })
        records.append(rec)
    return records


def parse_cell4g_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    records = []
    for _, row in df.iterrows():
        def f(col):
            v = row.get(col)
            return None if v is None or str(v).strip() == "" else v
        rec = _cell_common(row)
        rec.update({
            "chung_anten":     f("Chung anten"),
            "earfcn":          f("EARFCN"),
            "pci":             f("PCI"),
            "root_sequence_id": f("Root Sequence ID"),
        })
        records.append(rec)
    return records


def parse_cell5g_excel(file_bytes: bytes) -> List[Dict[str, Any]]:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    records = []
    for _, row in df.iterrows():
        def f(col):
            v = row.get(col)
            return None if v is None or str(v).strip() == "" else v
        rec = _cell_common(row)
        rec.update({
            "nr_arfcn":        f("NR-ARFCN"),
            "pci":             f("PCI"),
            "root_sequence_id": f("Root Sequence ID"),
        })
        records.append(rec)
    return records
""")

    # ── app/utils ─────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/backend/app/utils/__init__.py", "")

    write_file(f"{BASE_DIR}/backend/app/utils/deps.py", """\
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.core.security import decode_access_token
from app.models.user import User, UserRole

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    payload = decode_access_token(token)
    if not payload:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Invalid or expired token")
    user = db.query(User).filter(User.username == payload.get("sub")).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="User not found or inactive")
    return user


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if current_user.role != UserRole.admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Admin access required")
    return current_user
""")

    write_file(f"{BASE_DIR}/backend/app/utils/audit.py", """\
import json
from sqlalchemy.orm import Session
from app.models.audit_log import AuditLog
from app.models.user import User


def log_action(
    db: Session,
    user: User,
    action: str,
    table_name: str,
    record_id: int,
    old_value: dict = None,
    new_value: dict = None,
):
    entry = AuditLog(
        user_id=user.id,
        username=user.username,
        action=action,
        table_name=table_name,
        record_id=record_id,
        old_value=json.dumps(old_value, ensure_ascii=False, default=str) if old_value else None,
        new_value=json.dumps(new_value, ensure_ascii=False, default=str) if new_value else None,
    )
    db.add(entry)
    db.commit()
""")

    # ── app/api/routes ────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/backend/app/api/__init__.py", "")
    write_file(f"{BASE_DIR}/backend/app/api/routes/__init__.py", "")

    write_file(f"{BASE_DIR}/backend/app/api/routes/auth.py", """\
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
    \"\"\"Future: redirect to SSO provider.\"\"\"
    return {"message": "SSO not yet configured. Use /auth/login with local credentials."}


@router.post("/sso/callback")
def sso_callback():
    \"\"\"Future: handle SSO authorization code callback.\"\"\"
    return {"message": "SSO callback placeholder"}
""")

    write_file(f"{BASE_DIR}/backend/app/api/routes/users.py", """\
from typing import List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.user import User, UserRole
from app.schemas.user import UserRead, UserCreate, UserUpdate
from app.services.auth import create_user
from app.core.security import get_password_hash
from app.utils.deps import get_current_user, require_admin

router = APIRouter()


@router.get("/", response_model=List[UserRead])
def list_users(db: Session = Depends(get_db), _=Depends(require_admin)):
    return db.query(User).all()


@router.post("/", response_model=UserRead)
def create_new_user(
    payload: UserCreate,
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    existing = db.query(User).filter(
        (User.email == payload.email) | (User.username == payload.username)
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email or username already exists")
    return create_user(
        db, payload.email, payload.username,
        payload.password, payload.full_name or "", payload.role,
    )


@router.put("/{user_id}", response_model=UserRead)
def update_user(
    user_id: int,
    payload: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.admin and current_user.id != user_id:
        raise HTTPException(status_code=403, detail="Not allowed")
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if payload.full_name is not None:
        user.full_name = payload.full_name
    if payload.password:
        user.hashed_password = get_password_hash(payload.password)
    if current_user.role == UserRole.admin:
        if payload.role is not None:
            user.role = payload.role
        if payload.is_active is not None:
            user.is_active = payload.is_active
    db.commit()
    db.refresh(user)
    return user


@router.delete("/{user_id}")
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    db.delete(user)
    db.commit()
    return {"message": "Deleted"}
""")

    write_file(f"{BASE_DIR}/backend/app/api/routes/sites.py", """\
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.site import Site
from app.schemas.site import SiteCreate, SiteUpdate, SiteRead
from app.utils.deps import get_current_user
from app.utils.audit import log_action
from app.models.user import User
from app.services.import_excel import parse_site_excel

router = APIRouter()


def _site_or_404(db: Session, site_id: int) -> Site:
    s = db.query(Site).filter(Site.id == site_id).first()
    if not s:
        raise HTTPException(status_code=404, detail="Site not found")
    return s


@router.get("/", response_model=List[SiteRead])
def list_sites(
    skip: int = 0,
    limit: int = 200,
    search: Optional[str] = Query(None),
    mien: Optional[str] = Query(None),
    tinh: Optional[str] = Query(None),
    tram_3g: Optional[bool] = Query(None),
    tram_4g: Optional[bool] = Query(None),
    tram_5g: Optional[bool] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Site)
    if search:
        q = q.filter(Site.site_name.ilike(f"%{search}%"))
    if mien:
        q = q.filter(Site.mien == mien)
    if tinh:
        q = q.filter(Site.tinh == tinh)
    if tram_3g is not None:
        q = q.filter(Site.tram_3g == tram_3g)
    if tram_4g is not None:
        q = q.filter(Site.tram_4g == tram_4g)
    if tram_5g is not None:
        q = q.filter(Site.tram_5g == tram_5g)
    return q.offset(skip).limit(limit).all()


@router.get("/count")
def count_sites(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {"count": db.query(Site).count()}


@router.get("/{site_id}", response_model=SiteRead)
def get_site(site_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    return _site_or_404(db, site_id)


@router.post("/", response_model=SiteRead, status_code=201)
def create_site(
    payload: SiteCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    site = Site(**payload.model_dump(), created_by=current_user.id)
    db.add(site)
    db.commit()
    db.refresh(site)
    log_action(db, current_user, "CREATE", "sites", site.id,
               new_value=payload.model_dump())
    return site


@router.put("/{site_id}", response_model=SiteRead)
def update_site(
    site_id: int,
    payload: SiteUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    site = _site_or_404(db, site_id)
    old = {c.name: getattr(site, c.name) for c in site.__table__.columns}
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(site, k, v)
    db.commit()
    db.refresh(site)
    log_action(db, current_user, "UPDATE", "sites", site.id,
               old_value=old, new_value=payload.model_dump(exclude_unset=True))
    return site


@router.delete("/{site_id}")
def delete_site(
    site_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    site = _site_or_404(db, site_id)
    db.delete(site)
    db.commit()
    log_action(db, current_user, "DELETE", "sites", site_id)
    return {"message": "Deleted"}


@router.post("/import-excel")
async def import_sites_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    content = await file.read()
    records = parse_site_excel(content)
    created, errors = 0, []
    for i, rec in enumerate(records):
        try:
            if not rec.get("site_name"):
                errors.append(f"Row {i+2}: missing site_name")
                continue
            existing = db.query(Site).filter(Site.site_name == rec["site_name"]).first()
            if existing:
                errors.append(f"Row {i+2}: site_name '{rec['site_name']}' already exists")
                continue
            site = Site(**rec, created_by=current_user.id)
            db.add(site)
            db.commit()
            created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Row {i+2}: {str(e)}")
    return {"created": created, "errors": errors}
""")

    # ── cell routes (generated) ───────────────────────────────────────
    for tech in ("3g", "4g", "5g"):
        TU = tech.upper()
        write_file(f"{BASE_DIR}/backend/app/api/routes/cells_{tech}.py", f"""\
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.cell_{tech} import Cell{TU}
from app.schemas.cell import Cell{TU}Create, Cell{TU}Update, Cell{TU}Read
from app.utils.deps import get_current_user
from app.utils.audit import log_action
from app.models.user import User
from app.services.import_excel import parse_cell{tech}_excel

router = APIRouter()


def _or_404(db: Session, record_id: int) -> Cell{TU}:
    obj = db.query(Cell{TU}).filter(Cell{TU}.id == record_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Cell not found")
    return obj


@router.get("/", response_model=List[Cell{TU}Read])
def list_cells(
    skip: int = 0,
    limit: int = 200,
    search: Optional[str] = Query(None),
    mien: Optional[str] = Query(None),
    tinh: Optional[str] = Query(None),
    vendor: Optional[str] = Query(None),
    mimo: Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Cell{TU})
    if search:
        q = q.filter(
            Cell{TU}.cell_name.ilike(f"%{{search}}%") |
            Cell{TU}.site_name.ilike(f"%{{search}}%")
        )
    if mien:
        q = q.filter(Cell{TU}.mien == mien)
    if tinh:
        q = q.filter(Cell{TU}.tinh == tinh)
    if vendor:
        q = q.filter(Cell{TU}.vendor == vendor)
    if mimo:
        q = q.filter(Cell{TU}.mimo == mimo)
    if vung_phu_song:
        q = q.filter(Cell{TU}.vung_phu_song == vung_phu_song)
    return q.offset(skip).limit(limit).all()


@router.get("/count")
def count_cells(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return {{"count": db.query(Cell{TU}).count()}}


@router.get("/{{cell_id}}", response_model=Cell{TU}Read)
def get_cell(cell_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    return _or_404(db, cell_id)


@router.post("/", response_model=Cell{TU}Read, status_code=201)
def create_cell(
    payload: Cell{TU}Create,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = Cell{TU}(**payload.model_dump(), created_by=current_user.id)
    db.add(cell)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "CREATE", "cells_{tech}", cell.id,
               new_value=payload.model_dump())
    return cell


@router.put("/{{cell_id}}", response_model=Cell{TU}Read)
def update_cell(
    cell_id: int,
    payload: Cell{TU}Update,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = _or_404(db, cell_id)
    old = {{c.name: getattr(cell, c.name) for c in cell.__table__.columns}}
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(cell, k, v)
    db.commit()
    db.refresh(cell)
    log_action(db, current_user, "UPDATE", "cells_{tech}", cell.id,
               old_value=old, new_value=payload.model_dump(exclude_unset=True))
    return cell


@router.delete("/{{cell_id}}")
def delete_cell(
    cell_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cell = _or_404(db, cell_id)
    db.delete(cell)
    db.commit()
    log_action(db, current_user, "DELETE", "cells_{tech}", cell_id)
    return {{"message": "Deleted"}}


@router.post("/import-excel")
async def import_excel(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.models.site import Site
    content = await file.read()
    records = parse_cell{tech}_excel(content)
    created, errors = 0, []
    for i, rec in enumerate(records):
        try:
            site = db.query(Site).filter(
                Site.site_name == rec.get("site_name")
            ).first()
            if not site:
                errors.append(
                    f"Row {{i+2}}: site_name '{{rec.get('site_name')}}' not found"
                )
                continue
            rec["site_id"] = site.id
            cell = Cell{TU}(**rec, created_by=current_user.id)
            db.add(cell)
            db.commit()
            created += 1
        except Exception as e:
            db.rollback()
            errors.append(f"Row {{i+2}}: {{str(e)}}")
    return {{"created": created, "errors": errors}}
""")

    write_file(f"{BASE_DIR}/backend/app/api/routes/dropdowns.py", """\
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.dropdown import (
    DropdownTinhXaPhuong, DropdownAntenna, DropdownVendor, DropdownGeneral,
)
from app.utils.deps import get_current_user

router = APIRouter()


@router.get("/tinh-xa-phuong")
def get_tinh_xa_phuong(db: Session = Depends(get_db), _=Depends(get_current_user)):
    rows = db.query(DropdownTinhXaPhuong).all()
    return [
        {
            "id": r.id, "mien": r.mien, "ten_tinh": r.ten_tinh,
            "ten_phuong_xa": r.ten_phuong_xa, "ma_tinh": r.ma_tinh,
            "ma_phuong_xa": r.ma_phuong_xa, "ky_tu_1_6": r.ky_tu_1_6,
        }
        for r in rows
    ]


@router.get("/antenna")
def get_antenna(db: Session = Depends(get_db), _=Depends(get_current_user)):
    rows = db.query(DropdownAntenna).all()
    return [
        {"id": r.id, "name": r.name, "band": r.band,
         "no_of_ports": r.no_of_ports, "gain": r.gain}
        for r in rows
    ]


@router.get("/vendor")
def get_vendor(db: Session = Depends(get_db), _=Depends(get_current_user)):
    rows = db.query(DropdownVendor).all()
    return [
        {"id": r.id, "vendor_2g": r.vendor_2g, "vendor_3g": r.vendor_3g,
         "vendor_4g": r.vendor_4g, "vendor_5g": r.vendor_5g}
        for r in rows
    ]


@router.get("/general/{category}")
def get_general(
    category: str,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    rows = db.query(DropdownGeneral).filter(
        DropdownGeneral.category == category
    ).all()
    return [{"id": r.id, "value": r.value, "label": r.label} for r in rows]
""")

    write_file(f"{BASE_DIR}/backend/app/api/routes/report.py", """\
from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.db.session import get_db
from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G
from app.utils.deps import get_current_user

router = APIRouter()


@router.get("/summary")
def report_summary(
    mien: Optional[str] = Query(None),
    tinh: Optional[str] = Query(None),
    vendor: Optional[str] = Query(None),
    mimo: Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    site_q = db.query(Site)
    if mien:
        site_q = site_q.filter(Site.mien == mien)
    if tinh:
        site_q = site_q.filter(Site.tinh == tinh)
    sites = site_q.all()

    def cell_count(Model, site_id: int) -> int:
        q = db.query(func.count(Model.id)).filter(Model.site_id == site_id)
        if vendor:
            q = q.filter(Model.vendor == vendor)
        if mimo:
            q = q.filter(Model.mimo == mimo)
        if vung_phu_song:
            q = q.filter(Model.vung_phu_song == vung_phu_song)
        return q.scalar() or 0

    result = []
    for site in sites:
        c3g = cell_count(Cell3G, site.id)
        c4g = cell_count(Cell4G, site.id)
        c5g = cell_count(Cell5G, site.id)
        result.append({
            "mien":     site.mien,
            "tinh":     site.tinh,
            "site_name": site.site_name,
            "site_2g":  1 if site.tram_2g else 0,
            "site_3g":  1 if site.tram_3g else 0,
            "site_4g":  1 if site.tram_4g else 0,
            "site_5g":  1 if site.tram_5g else 0,
            "cell_2g":  0,
            "cell_3g":  c3g,
            "cell_4g":  c4g,
            "cell_5g":  c5g,
        })

    totals = {
        "mien": "TONG", "tinh": "", "site_name": "",
        "site_2g": sum(r["site_2g"] for r in result),
        "site_3g": sum(r["site_3g"] for r in result),
        "site_4g": sum(r["site_4g"] for r in result),
        "site_5g": sum(r["site_5g"] for r in result),
        "cell_2g": 0,
        "cell_3g": sum(r["cell_3g"] for r in result),
        "cell_4g": sum(r["cell_4g"] for r in result),
        "cell_5g": sum(r["cell_5g"] for r in result),
    }
    return {"rows": result, "totals": totals}


@router.get("/export-csv")
def export_csv(
    mien: Optional[str] = Query(None),
    tinh: Optional[str] = Query(None),
    vendor: Optional[str] = Query(None),
    mimo: Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    from fastapi.responses import StreamingResponse
    import csv, io
    data = report_summary(
        mien=mien, tinh=tinh, vendor=vendor,
        mimo=mimo, vung_phu_song=vung_phu_song, db=db,
    )
    rows = data["rows"]
    output = io.StringIO()
    if rows:
        writer = csv.DictWriter(output, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=report.csv"},
    )
""")

    write_file(f"{BASE_DIR}/backend/app/api/routes/audit.py", """\
from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.audit_log import AuditLog
from app.utils.deps import require_admin

router = APIRouter()


@router.get("/")
def list_audit_logs(
    skip: int = 0,
    limit: int = 100,
    table_name: Optional[str] = Query(None),
    action: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    q = db.query(AuditLog).order_by(AuditLog.timestamp.desc())
    if table_name:
        q = q.filter(AuditLog.table_name == table_name)
    if action:
        q = q.filter(AuditLog.action == action)
    logs = q.offset(skip).limit(limit).all()
    return [
        {
            "id": log.id,
            "username": log.username,
            "action": log.action,
            "table_name": log.table_name,
            "record_id": log.record_id,
            "old_value": log.old_value,
            "new_value": log.new_value,
            "timestamp": log.timestamp.isoformat() if log.timestamp else None,
        }
        for log in logs
    ]
""")

    # ── app/main.py ───────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/backend/app/main.py", """\
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db.session import engine, SessionLocal
from app.db import base  # noqa – registers all models
from app.db.base import Base
from app.api.routes import (
    auth, users, sites, cells_3g, cells_4g, cells_5g,
    dropdowns, report, audit,
)

Base.metadata.create_all(bind=engine)


def _seed_initial_data():
    db = SessionLocal()
    try:
        from app.models.user import User, UserRole
        from app.core.security import get_password_hash
        from app.models.dropdown import DropdownGeneral, DropdownVendor

        # Admin user
        if not db.query(User).filter(User.username == "admin").first():
            db.add(User(
                email="admin@sitelink.local",
                username="admin",
                full_name="Administrator",
                hashed_password=get_password_hash("admin"),
                role=UserRole.admin,
            ))
            db.commit()

        def seed_cat(cat, values):
            if db.query(DropdownGeneral).filter(
                    DropdownGeneral.category == cat).count() == 0:
                for v in values:
                    db.add(DropdownGeneral(category=cat, value=v, label=v))
                db.commit()

        seed_cat("moran",          ["VNPT HOST", "MBF HOST"])
        seed_cat("phan_loai_tram", ["IBC", "Macro outdoor", "IBC + Outdoor",
                                     "Smallcell", "miniDAS"])
        seed_cat("mien",           ["MB", "MT", "MN"])
        seed_cat("vung_phu_song",  ["Indoor", "Outdoor"])
        seed_cat("mimo",           ["2x2", "4x4", "8x8"])
        seed_cat("site_vip",       ["VIP", "VVIP"])
        seed_cat("csht", [
            "VNPT", "MOBIFONE", "XA HOI HOA", "VIETTEL",
            "LIEN KET", "HA TANG CO SAN", "GTEL", "IBC", "VIETNAMMOBILE",
        ])

        if db.query(DropdownVendor).count() == 0:
            for row in [
                ("Alcatel",  "Alcatel",  "Nokia",    "Nokia"),
                ("Nokia",    "Nokia",    "Ericsson", "Ericsson"),
                ("Ericsson", "Ericsson", "Huawei",   "Huawei"),
                ("Huawei",   "Huawei",   "ZTE",      "ZTE"),
                ("ZTE",      "ZTE",      "Samsung",  "Samsung"),
            ]:
                db.add(DropdownVendor(
                    vendor_2g=row[0], vendor_3g=row[1],
                    vendor_4g=row[2], vendor_5g=row[3],
                ))
            db.commit()
    finally:
        db.close()


app = FastAPI(
    title="SiteLink API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup():
    _seed_initial_data()


PREFIX = "/api/v1"
app.include_router(auth.router,      prefix=f"{PREFIX}/auth",      tags=["Auth"])
app.include_router(users.router,     prefix=f"{PREFIX}/users",     tags=["Users"])
app.include_router(sites.router,     prefix=f"{PREFIX}/sites",     tags=["Sites"])
app.include_router(cells_3g.router,  prefix=f"{PREFIX}/cells-3g",  tags=["Cells-3G"])
app.include_router(cells_4g.router,  prefix=f"{PREFIX}/cells-4g",  tags=["Cells-4G"])
app.include_router(cells_5g.router,  prefix=f"{PREFIX}/cells-5g",  tags=["Cells-5G"])
app.include_router(dropdowns.router, prefix=f"{PREFIX}/dropdowns", tags=["Dropdowns"])
app.include_router(report.router,    prefix=f"{PREFIX}/report",    tags=["Report"])
app.include_router(audit.router,     prefix=f"{PREFIX}/audit",     tags=["Audit"])


@app.get("/health")
def health():
    return {"status": "ok"}
""")

    # ── postgres init ─────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/postgres/init/01_seed.sql", "SELECT 1;\n")

    # ================================================================== #
    #  FRONTEND
    # ================================================================== #

    write_file(f"{BASE_DIR}/frontend/Dockerfile", """\
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
""")

    write_file(f"{BASE_DIR}/frontend/nginx.conf", """\
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;
    location / {
        try_files $uri $uri/ /index.html;
    }
}
""")

    write_file(f"{BASE_DIR}/frontend/package.json", """\
{
  "name": "sitelink-frontend",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.23.1",
    "antd": "^5.18.3",
    "@ant-design/icons": "^5.3.7",
    "axios": "^1.7.2",
    "zustand": "^4.5.2",
    "dayjs": "^1.11.11",
    "recharts": "^2.12.7",
    "react-hot-toast": "^2.4.1"
  },
  "devDependencies": {
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.1",
    "typescript": "^5.4.5",
    "vite": "^5.3.1"
  }
}
""")

    write_file(f"{BASE_DIR}/frontend/tsconfig.json", """\
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
""")

    write_file(f"{BASE_DIR}/frontend/tsconfig.node.json", """\
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts"]
}
""")

    write_file(f"{BASE_DIR}/frontend/vite.config.ts", """\
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: {
    proxy: {
      '/api': { target: 'http://localhost:8000', changeOrigin: true },
    },
  },
})
""")

    write_file(f"{BASE_DIR}/frontend/index.html", """\
<!doctype html>
<html lang="vi">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>SiteLink</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
""")

    write_file(f"{BASE_DIR}/frontend/src/main.tsx", """\
import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import 'antd/dist/reset.css'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>,
)
""")

    write_file(f"{BASE_DIR}/frontend/src/index.css", """\
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  background: #f0f2f5;
}
""")

    # ── types ─────────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/types/index.ts", """\
export interface User {
  id: number
  email: string
  username: string
  full_name?: string
  role: 'admin' | 'user'
  is_active: boolean
  auth_provider: 'local' | 'sso'
}

export interface Site {
  id: number
  mien: string
  tinh: string
  phuong_xa?: string
  site_name_cu?: string
  site_name: string
  site_vip?: string
  lat: number
  long: number
  tram_2g: boolean
  tram_3g: boolean
  tram_4g: boolean
  tram_5g: boolean
  repeater: boolean
  booster: boolean
  node_truyen_dan_only: boolean
  phan_loai_tram?: string
  tram_phu_song_tsca?: string
  moran_3g?: string
  moran_4g?: string
  moran_5g?: string
  ma_ptm: string
  do_cao_dinh_cot_anten?: number
  do_cao_cot_anten?: number
  dia_chi?: string
  ghi_chu?: string
}

export interface CellBase {
  id: number
  site_id: number
  mien?: string
  tinh?: string
  phuong_xa?: string
  site_name: string
  cell_name: string
  cell_vip?: string
  moran?: string
  lat?: number
  long?: number
  vung_phu_song?: string
  vendor?: string
  do_cao_anten?: number
  azimuth?: number
  m_tilt?: number
  e_tilt?: number
  total_tilt?: number
  loai_anten?: string
  baseband?: string
  rf?: string
  cell_id?: string
  mimo?: string
}

export interface Cell3G extends CellBase {
  chung_anten?: string
  arfcn?: string
  psc?: string
}

export interface Cell4G extends CellBase {
  chung_anten?: string
  earfcn?: string
  pci?: string
  root_sequence_id?: string
}

export interface Cell5G extends CellBase {
  nr_arfcn?: string
  pci?: string
  root_sequence_id?: string
}

export interface ReportRow {
  mien?: string
  tinh?: string
  site_name?: string
  site_2g: number
  site_3g: number
  site_4g: number
  site_5g: number
  cell_2g: number
  cell_3g: number
  cell_4g: number
  cell_5g: number
}

export interface AuditLog {
  id: number
  username: string
  action: string
  table_name: string
  record_id: number
  old_value?: string
  new_value?: string
  timestamp: string
}
""")

    # ── api layer ─────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/api/client.ts", """\
import axios from 'axios'

const api = axios.create({ baseURL: '' })

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('sl_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

api.interceptors.response.use(
  (r) => r,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('sl_token')
      window.location.href = '/login'
    }
    return Promise.reject(err)
  },
)

export default api
""")

    write_file(f"{BASE_DIR}/frontend/src/api/auth.ts", """\
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
""")

    write_file(f"{BASE_DIR}/frontend/src/api/sites.ts", """\
import api from './client'
import type { Site } from '@/types'

export const getSites = (params?: Record<string, unknown>) =>
  api.get<Site[]>('/api/v1/sites/', { params }).then((r) => r.data)

export const getSite = (id: number) =>
  api.get<Site>(`/api/v1/sites/${id}`).then((r) => r.data)

export const createSite = (data: Partial<Site>) =>
  api.post<Site>('/api/v1/sites/', data).then((r) => r.data)

export const updateSite = (id: number, data: Partial<Site>) =>
  api.put<Site>(`/api/v1/sites/${id}`, data).then((r) => r.data)

export const deleteSite = (id: number) =>
  api.delete(`/api/v1/sites/${id}`)

export const importSitesExcel = (file: File) => {
  const form = new FormData()
  form.append('file', file)
  return api.post<{ created: number; errors: string[] }>(
    '/api/v1/sites/import-excel', form,
  ).then((r) => r.data)
}
""")

    write_file(f"{BASE_DIR}/frontend/src/api/cells.ts", """\
import api from './client'
import type { Cell3G, Cell4G, Cell5G } from '@/types'

function makeCellApi<T>(tech: string) {
  return {
    list: (params?: Record<string, unknown>) =>
      api.get<T[]>(`/api/v1/cells-${tech}/`, { params }).then((r) => r.data),
    get: (id: number) =>
      api.get<T>(`/api/v1/cells-${tech}/${id}`).then((r) => r.data),
    create: (data: Partial<T>) =>
      api.post<T>(`/api/v1/cells-${tech}/`, data).then((r) => r.data),
    update: (id: number, data: Partial<T>) =>
      api.put<T>(`/api/v1/cells-${tech}/${id}`, data).then((r) => r.data),
    remove: (id: number) =>
      api.delete(`/api/v1/cells-${tech}/${id}`),
    importExcel: (file: File) => {
      const form = new FormData()
      form.append('file', file)
      return api
        .post<{ created: number; errors: string[] }>(
          `/api/v1/cells-${tech}/import-excel`, form,
        )
        .then((r) => r.data)
    },
  }
}

export const cells3gApi = makeCellApi<Cell3G>('3g')
export const cells4gApi = makeCellApi<Cell4G>('4g')
export const cells5gApi = makeCellApi<Cell5G>('5g')
""")

    write_file(f"{BASE_DIR}/frontend/src/api/report.ts", """\
import api from './client'

export const getReport = (params?: Record<string, unknown>) =>
  api.get('/api/v1/report/summary', { params }).then((r) => r.data)

export const getAuditLogs = (params?: Record<string, unknown>) =>
  api.get('/api/v1/audit/', { params }).then((r) => r.data)

export const getDropdown = (category: string) =>
  api.get(`/api/v1/dropdowns/general/${category}`).then((r) => r.data)

export const getVendors = () =>
  api.get('/api/v1/dropdowns/vendor').then((r) => r.data)

export const getTinhXaPhuong = () =>
  api.get('/api/v1/dropdowns/tinh-xa-phuong').then((r) => r.data)
""")

    # ── store ─────────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/store/auth.ts", """\
import { create } from 'zustand'
import type { User } from '@/types'

interface AuthState {
  user: User | null
  token: string | null
  setAuth: (user: User, token: string) => void
  logout: () => void
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  token: localStorage.getItem('sl_token'),
  setAuth: (user, token) => {
    localStorage.setItem('sl_token', token)
    set({ user, token })
  },
  logout: () => {
    localStorage.removeItem('sl_token')
    set({ user: null, token: null })
  },
}))
""")

    # ── App.tsx ───────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/App.tsx", """\
import React, { useEffect } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { Toaster } from 'react-hot-toast'
import { useAuthStore } from '@/store/auth'
import { getMe } from '@/api/auth'

import LoginPage       from '@/pages/auth/LoginPage'
import MainLayout      from '@/components/layout/MainLayout'
import DashboardPage   from '@/pages/dashboard/DashboardPage'
import ReportPage      from '@/pages/dashboard/ReportPage'
import SitesPage       from '@/pages/sites/SitesPage'
import SiteFormPage    from '@/pages/sites/SiteFormPage'
import Cells3GPage     from '@/pages/cells/Cells3GPage'
import Cells4GPage     from '@/pages/cells/Cells4GPage'
import Cells5GPage     from '@/pages/cells/Cells5GPage'
import UsersPage       from '@/pages/admin/UsersPage'
import AuditPage       from '@/pages/admin/AuditPage'

function PrivateRoute({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.token)
  return token ? <>{children}</> : <Navigate to="/login" replace />
}

function AdminRoute({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user)
  if (!user) return <Navigate to="/login" replace />
  if (user.role !== 'admin') return <Navigate to="/" replace />
  return <>{children}</>
}

export default function App() {
  const { token, setAuth, logout } = useAuthStore()

  useEffect(() => {
    if (token) {
      getMe().then((u) => setAuth(u, token)).catch(() => logout())
    }
  }, [])

  return (
    <>
      <Toaster position="top-right" />
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route
          path="/"
          element={
            <PrivateRoute>
              <MainLayout />
            </PrivateRoute>
          }
        >
          <Route index element={<DashboardPage />} />
          <Route path="report"          element={<ReportPage />} />
          <Route path="sites"           element={<SitesPage />} />
          <Route path="sites/new"       element={<SiteFormPage />} />
          <Route path="sites/:id/edit"  element={<SiteFormPage />} />
          <Route path="cells/3g"        element={<Cells3GPage />} />
          <Route path="cells/4g"        element={<Cells4GPage />} />
          <Route path="cells/5g"        element={<Cells5GPage />} />
          <Route path="admin/users"     element={<AdminRoute><UsersPage /></AdminRoute>} />
          <Route path="admin/audit"     element={<AdminRoute><AuditPage /></AdminRoute>} />
        </Route>
      </Routes>
    </>
  )
}
""")

    # ── MainLayout ────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/components/layout/MainLayout.tsx", """\
import React, { useState } from 'react'
import { Layout, Menu, Avatar, Dropdown, Space, Typography } from 'antd'
import {
  DashboardOutlined, DatabaseOutlined, TableOutlined,
  BarChartOutlined, UserOutlined, AuditOutlined,
  LogoutOutlined, MenuFoldOutlined, MenuUnfoldOutlined,
} from '@ant-design/icons'
import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store/auth'

const { Sider, Header, Content } = Layout

export default function MainLayout() {
  const [collapsed, setCollapsed] = useState(false)
  const navigate   = useNavigate()
  const location   = useLocation()
  const { user, logout } = useAuthStore()

  const menuItems = [
    { key: '/',       icon: <DashboardOutlined />, label: 'Dashboard' },
    { key: '/report', icon: <BarChartOutlined />,  label: 'Bao cao tong hop' },
    { key: '/sites',  icon: <DatabaseOutlined />,  label: 'Quan ly Site' },
    {
      key: 'cells',
      icon: <TableOutlined />,
      label: 'Quan ly Cell',
      children: [
        { key: '/cells/3g', label: 'Cell 3G' },
        { key: '/cells/4g', label: 'Cell 4G' },
        { key: '/cells/5g', label: 'Cell 5G' },
      ],
    },
    ...(user?.role === 'admin'
      ? [{
          key: 'admin',
          icon: <AuditOutlined />,
          label: 'Quan tri',
          children: [
            { key: '/admin/users', label: 'Nguoi dung' },
            { key: '/admin/audit', label: 'Audit Log' },
          ],
        }]
      : []),
  ]

  const userMenu = {
    items: [{
      key: 'logout',
      icon: <LogoutOutlined />,
      label: 'Dang xuat',
      onClick: () => { logout(); navigate('/login') },
    }],
  }

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider collapsible collapsed={collapsed} onCollapse={setCollapsed}
             theme="dark" width={220}>
        <div style={{
          height: 48, display: 'flex', alignItems: 'center',
          justifyContent: 'center', color: '#fff',
          fontWeight: 700, fontSize: collapsed ? 14 : 18,
          borderBottom: '1px solid #333',
        }}>
          {collapsed ? 'SL' : 'SiteLink'}
        </div>
        <Menu
          theme="dark"
          mode="inline"
          selectedKeys={[location.pathname]}
          defaultOpenKeys={['cells', 'admin']}
          items={menuItems}
          onClick={({ key }) => {
            if (!['cells', 'admin'].includes(key)) navigate(key)
          }}
        />
      </Sider>

      <Layout>
        <Header style={{
          background: '#fff', padding: '0 24px',
          display: 'flex', alignItems: 'center',
          justifyContent: 'space-between',
          borderBottom: '1px solid #f0f0f0',
        }}>
          <Space>
            {collapsed
              ? <MenuUnfoldOutlined onClick={() => setCollapsed(false)}
                                    style={{ fontSize: 18, cursor: 'pointer' }} />
              : <MenuFoldOutlined   onClick={() => setCollapsed(true)}
                                    style={{ fontSize: 18, cursor: 'pointer' }} />}
            <Typography.Text strong style={{ fontSize: 16 }}>
              He thong quan ly du lieu toi uu
            </Typography.Text>
          </Space>
          <Dropdown menu={userMenu}>
            <Space style={{ cursor: 'pointer' }}>
              <Avatar icon={<UserOutlined />} style={{ backgroundColor: '#1890ff' }} />
              <span>{user?.full_name || user?.username}</span>
            </Space>
          </Dropdown>
        </Header>

        <Content style={{
          margin: 16, padding: 16,
          background: '#fff', borderRadius: 8,
          minHeight: 'calc(100vh - 112px)',
          overflowY: 'auto',
        }}>
          <Outlet />
        </Content>
      </Layout>
    </Layout>
  )
}
""")

    # ── LoginPage ─────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/pages/auth/LoginPage.tsx", """\
import React, { useState } from 'react'
import { Form, Input, Button, Card, Typography, Alert } from 'antd'
import { UserOutlined, LockOutlined } from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { login, getMe } from '@/api/auth'
import { useAuthStore } from '@/store/auth'

export default function LoginPage() {
  const navigate = useNavigate()
  const setAuth  = useAuthStore((s) => s.setAuth)
  const [error,   setError]   = useState('')
  const [loading, setLoading] = useState(false)

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

  return (
    <div style={{
      minHeight: '100vh', display: 'flex',
      alignItems: 'center', justifyContent: 'center',
      background: 'linear-gradient(135deg,#1a1a2e,#16213e,#0f3460)',
    }}>
      <Card style={{ width: 400, borderRadius: 12,
                     boxShadow: '0 20px 60px rgba(0,0,0,.3)' }}>
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <div style={{ fontSize: 48 }}>&#128225;</div>
          <Typography.Title level={2} style={{ margin: 0 }}>SiteLink</Typography.Title>
          <Typography.Text type="secondary">
            He thong quan ly du lieu toi uu
          </Typography.Text>
        </div>

        {error && (
          <Alert message={error} type="error" showIcon style={{ marginBottom: 16 }} />
        )}

        <Form layout="vertical" onFinish={onFinish} autoComplete="off">
          <Form.Item name="username" rules={[{ required: true, message: 'Nhap ten dang nhap' }]}>
            <Input prefix={<UserOutlined />} placeholder="Ten dang nhap" size="large" />
          </Form.Item>
          <Form.Item name="password" rules={[{ required: true, message: 'Nhap mat khau' }]}>
            <Input.Password prefix={<LockOutlined />} placeholder="Mat khau" size="large" />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" block size="large" loading={loading}>
              Dang nhap
            </Button>
          </Form.Item>
        </Form>

        <div style={{ textAlign: 'center' }}>
          <Typography.Text type="secondary" style={{ fontSize: 12 }}>
            SSO integration - coming soon
          </Typography.Text>
        </div>
      </Card>
    </div>
  )
}
""")

    # ── DashboardPage ─────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/pages/dashboard/DashboardPage.tsx", """\
import React, { useEffect, useState } from 'react'
import { Row, Col, Card, Statistic, Typography } from 'antd'
import {
  DatabaseOutlined, PartitionOutlined,
  WifiOutlined, RiseOutlined,
} from '@ant-design/icons'
import api from '@/api/client'

export default function DashboardPage() {
  const [counts, setCounts] = useState({ sites: 0, c3g: 0, c4g: 0, c5g: 0 })

  useEffect(() => {
    Promise.all([
      api.get('/api/v1/sites/count'),
      api.get('/api/v1/cells-3g/count'),
      api.get('/api/v1/cells-4g/count'),
      api.get('/api/v1/cells-5g/count'),
    ]).then(([s, c3, c4, c5]) => {
      setCounts({
        sites: s.data.count,
        c3g:   c3.data.count,
        c4g:   c4.data.count,
        c5g:   c5.data.count,
      })
    })
  }, [])

  const stats = [
    { title: 'Tong so Site', value: counts.sites, icon: <DatabaseOutlined />,  color: '#1890ff' },
    { title: 'Cell 3G',      value: counts.c3g,   icon: <PartitionOutlined />, color: '#52c41a' },
    { title: 'Cell 4G',      value: counts.c4g,   icon: <WifiOutlined />,      color: '#faad14' },
    { title: 'Cell 5G',      value: counts.c5g,   icon: <RiseOutlined />,      color: '#f5222d' },
  ]

  return (
    <div>
      <Typography.Title level={3}>Dashboard</Typography.Title>
      <Row gutter={[16, 16]}>
        {stats.map((s) => (
          <Col xs={24} sm={12} lg={6} key={s.title}>
            <Card>
              <Statistic
                title={s.title}
                value={s.value}
                prefix={React.cloneElement(
                  s.icon as React.ReactElement,
                  { style: { color: s.color } },
                )}
                valueStyle={{ color: s.color }}
              />
            </Card>
          </Col>
        ))}
      </Row>
    </div>
  )
}
""")

    # ── ReportPage ────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/pages/dashboard/ReportPage.tsx", """\
import React, { useState, useEffect } from 'react'
import {
  Typography, Form, Row, Col, Select, Button,
  Table, Space, Tag, Divider,
} from 'antd'
import { SearchOutlined, DownloadOutlined, ClearOutlined } from '@ant-design/icons'
import { getReport, getVendors } from '@/api/report'
import type { ReportRow } from '@/types'

export default function ReportPage() {
  const [form]    = Form.useForm()
  const [data,    setData]    = useState<ReportRow[]>([])
  const [totals,  setTotals]  = useState<ReportRow | null>(null)
  const [loading, setLoading] = useState(false)
  const [vendors, setVendors] = useState<string[]>([])

  useEffect(() => {
    getVendors().then((rows: any[]) => {
      const v = new Set<string>()
      rows.forEach((r: any) => { if (r.vendor_4g) v.add(r.vendor_4g) })
      setVendors([...v])
    })
  }, [])

  const onSearch = async (values: Record<string, string>) => {
    setLoading(true)
    try {
      const params = Object.fromEntries(
        Object.entries(values).filter(([, v]) => v !== undefined && v !== ''),
      )
      const res = await getReport(params)
      setData(res.rows)
      setTotals(res.totals)
    } finally {
      setLoading(false)
    }
  }

  const columns = [
    { title: 'Mien',   dataIndex: 'mien',      width: 70  },
    { title: 'Tinh',   dataIndex: 'tinh',      width: 150 },
    { title: 'Site',   dataIndex: 'site_name', width: 150 },
    { title: 'Site 2G', dataIndex: 'site_2g', width: 80,
      render: (v: number) => v ? <Tag color="green">{v}</Tag>  : '-' },
    { title: 'Site 3G', dataIndex: 'site_3g', width: 80,
      render: (v: number) => v ? <Tag color="blue">{v}</Tag>   : '-' },
    { title: 'Site 4G', dataIndex: 'site_4g', width: 80,
      render: (v: number) => v ? <Tag color="orange">{v}</Tag> : '-' },
    { title: 'Site 5G', dataIndex: 'site_5g', width: 80,
      render: (v: number) => v ? <Tag color="red">{v}</Tag>    : '-' },
    { title: 'Cell 3G', dataIndex: 'cell_3g', width: 80 },
    { title: 'Cell 4G', dataIndex: 'cell_4g', width: 80 },
    { title: 'Cell 5G', dataIndex: 'cell_5g', width: 80 },
  ]

  return (
    <div>
      <Typography.Title level={3}>Bao cao tong hop</Typography.Title>

      <Form form={form} layout="vertical" onFinish={onSearch}>
        <Row gutter={16}>
          <Col span={4}>
            <Form.Item name="mien" label="Mien">
              <Select allowClear placeholder="Tat ca">
                {['MB','MT','MN'].map((m) =>
                  <Select.Option key={m} value={m}>{m}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={4}>
            <Form.Item name="vendor" label="Vendor">
              <Select allowClear placeholder="Tat ca">
                {vendors.map((v) =>
                  <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={4}>
            <Form.Item name="mimo" label="MIMO">
              <Select allowClear placeholder="Tat ca">
                {['2x2','4x4','8x8'].map((m) =>
                  <Select.Option key={m} value={m}>{m}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={4}>
            <Form.Item name="vung_phu_song" label="Vung phu song">
              <Select allowClear placeholder="Tat ca">
                <Select.Option value="Indoor">Indoor</Select.Option>
                <Select.Option value="Outdoor">Outdoor</Select.Option>
              </Select>
            </Form.Item>
          </Col>
          <Col span={8} style={{ display:'flex', alignItems:'flex-end', paddingBottom:24 }}>
            <Space>
              <Button type="primary" icon={<SearchOutlined />}
                      htmlType="submit" loading={loading}>
                Tim kiem
              </Button>
              <Button icon={<ClearOutlined />} onClick={() => {
                form.resetFields(); setData([]); setTotals(null)
              }}>
                Xoa loc
              </Button>
              <Button icon={<DownloadOutlined />}
                      onClick={() => window.open('/api/v1/report/export-csv','_blank')}>
                Xuat CSV
              </Button>
            </Space>
          </Col>
        </Row>
      </Form>

      <Divider />

      {totals && (
        <Row gutter={8} style={{ marginBottom: 16 }}>
          {[
            { label:'Tong Site 2G', val:totals.site_2g, color:'#95de64' },
            { label:'Tong Site 3G', val:totals.site_3g, color:'#69b1ff' },
            { label:'Tong Site 4G', val:totals.site_4g, color:'#ffd666' },
            { label:'Tong Site 5G', val:totals.site_5g, color:'#ff7875' },
            { label:'Tong Cell 3G', val:totals.cell_3g, color:'#69b1ff' },
            { label:'Tong Cell 4G', val:totals.cell_4g, color:'#ffd666' },
            { label:'Tong Cell 5G', val:totals.cell_5g, color:'#ff7875' },
          ].map((t) => (
            <Col key={t.label}>
              <Tag color={t.color} style={{ fontSize:14, padding:'4px 12px' }}>
                {t.label}: <strong>{t.val}</strong>
              </Tag>
            </Col>
          ))}
        </Row>
      )}

      <Table
        columns={columns}
        dataSource={data}
        rowKey={(_, i) => String(i)}
        loading={loading}
        size="small"
        scroll={{ x: 900 }}
        pagination={{ pageSize: 50, showTotal: (t) => `${t} records` }}
      />
    </div>
  )
}
""")

    # ── SitesPage ─────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/pages/sites/SitesPage.tsx", """\
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, Upload, message, Row, Col,
} from 'antd'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { getSites, deleteSite, importSitesExcel } from '@/api/sites'
import type { Site } from '@/types'

export default function SitesPage() {
  const navigate  = useNavigate()
  const [sites,   setSites]   = useState<Site[]>([])
  const [loading, setLoading] = useState(false)
  const [search,  setSearch]  = useState('')
  const [mien,    setMien]    = useState<string | undefined>()

  const load = async () => {
    setLoading(true)
    try { setSites(await getSites({ search, mien, limit: 500 })) }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [search, mien])

  const handleDelete = async (id: number) => {
    await deleteSite(id)
    message.success('Da xoa site')
    load()
  }

  const handleImport = async (file: File) => {
    try {
      const res = await importSitesExcel(file)
      message.success(`Da nhap ${res.created} site`)
      if (res.errors?.length)
        message.warning(`${res.errors.length} loi - xem console`)
      load()
    } catch {
      message.error('Import that bai')
    }
    return false
  }

  const columns = [
    { title: 'Mien',      dataIndex: 'mien',      width: 70  },
    { title: 'Tinh',      dataIndex: 'tinh',      width: 140 },
    { title: 'Site Name', dataIndex: 'site_name', width: 150,
      render: (v: string) => <strong>{v}</strong> },
    { title: 'Lat',  dataIndex: 'lat',  width: 110 },
    { title: 'Long', dataIndex: 'long', width: 110 },
    {
      title: 'Cong nghe', width: 160,
      render: (_: unknown, r: Site) => (
        <Space size={2}>
          {r.tram_2g && <Tag color="default">2G</Tag>}
          {r.tram_3g && <Tag color="blue">3G</Tag>}
          {r.tram_4g && <Tag color="orange">4G</Tag>}
          {r.tram_5g && <Tag color="red">5G</Tag>}
        </Space>
      ),
    },
    { title: 'Loai tram', dataIndex: 'phan_loai_tram', width: 130 },
    { title: 'Ma PTM',    dataIndex: 'ma_ptm',         width: 120 },
    {
      title: 'Hanh dong', width: 110, fixed: 'right' as const,
      render: (_: unknown, r: Site) => (
        <Space>
          <Button size="small" icon={<EditOutlined />}
                  onClick={() => navigate(`/sites/${r.id}/edit`)} />
          <Popconfirm title="Xoa site nay?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quan ly Site</Typography.Title>
        <Space>
          <Upload beforeUpload={handleImport} accept=".xlsx,.xls" showUploadList={false}>
            <Button icon={<UploadOutlined />}>Import Excel</Button>
          </Upload>
          <Button type="primary" icon={<PlusOutlined />}
                  onClick={() => navigate('/sites/new')}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="300px">
          <Input
            prefix={<SearchOutlined />}
            placeholder="Tim site name..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            allowClear
          />
        </Col>
        <Col>
          <Select placeholder="Mien" allowClear style={{ width: 100 }}
                  onChange={(v) => setMien(v)}>
            {['MB','MT','MN'].map((m) =>
              <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
      </Row>

      <Table
        columns={columns}
        dataSource={sites}
        rowKey="id"
        loading={loading}
        size="small"
        scroll={{ x: 1000 }}
        pagination={{ pageSize: 50, showTotal: (t) => `${t} sites` }}
      />
    </div>
  )
}
""")

    # ── SiteFormPage ──────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/pages/sites/SiteFormPage.tsx", """\
import React, { useEffect, useState } from 'react'
import {
  Typography, Form, Input, Select, Switch, Button,
  Row, Col, Card, Space, InputNumber, message,
} from 'antd'
import { SaveOutlined, ArrowLeftOutlined } from '@ant-design/icons'
import { useNavigate, useParams } from 'react-router-dom'
import { getSite, createSite, updateSite } from '@/api/sites'
import { getDropdown } from '@/api/report'

export default function SiteFormPage() {
  const [form]    = Form.useForm()
  const navigate  = useNavigate()
  const { id }    = useParams<{ id: string }>()
  const isEdit    = Boolean(id)
  const [loading,      setLoading]      = useState(false)
  const [phanLoaiOpts, setPhanLoaiOpts] = useState<string[]>([])

  useEffect(() => {
    getDropdown('phan_loai_tram').then((rows: any[]) =>
      setPhanLoaiOpts(rows.map((r) => r.value)))
    if (isEdit && id) {
      getSite(Number(id)).then((site) => form.setFieldsValue(site))
    }
  }, [id])

  const onFinish = async (values: any) => {
    setLoading(true)
    try {
      if (isEdit) {
        await updateSite(Number(id), values)
        message.success('Cap nhat thanh cong')
      } else {
        await createSite(values)
        message.success('Tao site thanh cong')
      }
      navigate('/sites')
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Co loi xay ra')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div>
      <Space style={{ marginBottom: 16 }}>
        <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/sites')}>
          Quay lai
        </Button>
        <Typography.Title level={3} style={{ margin: 0 }}>
          {isEdit ? 'Chinh sua Site' : 'Them Site moi'}
        </Typography.Title>
      </Space>

      <Form form={form} layout="vertical" onFinish={onFinish}>
        <Card title="Thong tin chung" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={6}>
              <Form.Item name="mien" label="Mien" rules={[{ required: true }]}>
                <Select>
                  {['MB','MT','MN'].map((m) =>
                    <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={9}>
              <Form.Item name="tinh" label="Tinh" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={9}>
              <Form.Item name="phuong_xa" label="Phuong/Xa">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="site_name_cu" label="Site name (cu)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="site_name" label="Site name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={4}>
              <Form.Item name="site_vip" label="Site VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={4}>
              <Form.Item name="ma_ptm" label="Ma PTM" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Toa do and Col anten" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={6}>
              <Form.Item name="lat" label="Latitude" rules={[{ required: true }]}>
                <InputNumber style={{ width:'100%' }} precision={5} step={0.00001} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="long" label="Longitude" rules={[{ required: true }]}>
                <InputNumber style={{ width:'100%' }} precision={5} step={0.00001} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="do_cao_dinh_cot_anten" label="Do cao dinh cot anten (m)">
                <InputNumber style={{ width:'100%' }} min={0} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="do_cao_cot_anten" label="Do cao cot anten mat san (m)">
                <InputNumber style={{ width:'100%' }} min={0} />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Loai tram and Cong nghe" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={8}>
              <Form.Item name="phan_loai_tram" label="Phan loai tram">
                <Select allowClear>
                  {phanLoaiOpts.map((o) =>
                    <Select.Option key={o} value={o}>{o}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            {([
              ['tram_2g','Tram 2G'],['tram_3g','Tram 3G'],
              ['tram_4g','Tram 4G'],['tram_5g','Tram 5G'],
              ['repeater','Repeater'],['booster','Booster'],
              ['node_truyen_dan_only','Node truyen dan only'],
            ] as [string,string][]).map(([name, label]) => (
              <Col span={4} key={name}>
                <Form.Item name={name} label={label} valuePropName="checked">
                  <Switch />
                </Form.Item>
              </Col>
            ))}
          </Row>
          <Row gutter={16}>
            {([
              ['moran_3g','MORAN 3G'],
              ['moran_4g','MORAN 4G'],
              ['moran_5g','MORAN 5G'],
            ] as [string,string][]).map(([name, label]) => (
              <Col span={6} key={name}>
                <Form.Item name={name} label={label}>
                  <Select allowClear>
                    <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                    <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                  </Select>
                </Form.Item>
              </Col>
            ))}
          </Row>
        </Card>

        <Card title="Thong tin khac" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item name="dia_chi" label="Dia chi">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="ghi_chu" label="Ghi chu">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Space>
          <Button type="primary" htmlType="submit"
                  icon={<SaveOutlined />} loading={loading}>
            {isEdit ? 'Cap nhat' : 'Tao moi'}
          </Button>
          <Button onClick={() => navigate('/sites')}>Huy</Button>
        </Space>
      </Form>
    </div>
  )
}
""")

    # ── Cell pages (3G / 4G / 5G) ─────────────────────────────────────
    def write_cell_page(tech: str, extra_cols: list[tuple], extra_form_items: list[tuple]):
        TU = tech.upper()
        api_name = f"cells{tech}Api"

        extra_col_code = "\n    ".join(
            f'{{ title: "{col_title}", dataIndex: "{col_field}", width: {col_w} }},'
            for col_title, col_field, col_w in extra_cols
        )

        extra_form_code = "\n            ".join(
            f'<Col span={{8}}>'
            f'<Form.Item name="{fname}" label="{flabel}">'
            f'<Input /></Form.Item></Col>'
            for fname, flabel in extra_form_items
        )

        content = """\
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, Upload, message, Row, Col,
  Modal, Form, InputNumber,
} from 'antd'
import {
  PlusOutlined, UploadOutlined, SearchOutlined,
  EditOutlined, DeleteOutlined,
} from '@ant-design/icons'
import { """ + api_name + """ } from '@/api/cells'
import type { Cell""" + TU + """ } from '@/types'
import { getVendors } from '@/api/report'
import { getSites } from '@/api/sites'
import type { Site } from '@/types'

export default function Cells""" + TU + """Page() {
  const [data,    setData]    = useState<Cell""" + TU + """[]>([])
  const [loading, setLoading] = useState(false)
  const [search,  setSearch]  = useState('')
  const [vendor,  setVendor]  = useState<string | undefined>()
  const [vendors, setVendors] = useState<string[]>([])
  const [sites,   setSites]   = useState<Site[]>([])
  const [modalOpen, setModalOpen] = useState(false)
  const [editing,   setEditing]   = useState<Cell""" + TU + """ | null>(null)
  const [form] = Form.useForm()

  const load = async () => {
    setLoading(true)
    try { setData(await """ + api_name + """.list({ search, vendor, limit: 500 })) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getVendors().then((rows: any[]) => {
      const v = new Set<string>()
      rows.forEach((r: any) => { if (r.vendor_4g) v.add(r.vendor_4g) })
      setVendors([...v])
    })
    getSites({ limit: 2000 }).then(setSites)
  }, [search, vendor])

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell""" + TU + """) => {
    setEditing(r); form.setFieldsValue(r); setModalOpen(true)
  }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await """ + api_name + """.update(editing.id, values)
        message.success('Cap nhat thanh cong')
      } else {
        await """ + api_name + """.create(values)
        message.success('Tao cell thanh cong')
      }
      setModalOpen(false)
      load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Loi')
    }
  }

  const handleDelete = async (id: number) => {
    await """ + api_name + """.remove(id)
    message.success('Da xoa')
    load()
  }

  const handleImport = async (file: File) => {
    const res = await """ + api_name + """.importExcel(file)
    message.success(`Da nhap ${res.created} cell`)
    if (res.errors?.length) message.warning(`${res.errors.length} loi`)
    load()
    return false
  }

  const columns = [
    { title: 'Site Name',  dataIndex: 'site_name',  width: 130 },
    { title: 'Cell Name',  dataIndex: 'cell_name',  width: 130 },
    { title: 'Vendor',     dataIndex: 'vendor',     width: 100 },
    { title: 'Azimuth',    dataIndex: 'azimuth',    width: 80  },
    { title: 'Do cao anten', dataIndex: 'do_cao_anten', width: 110 },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag>{v}</Tag> : '-' },
    { title: 'Vung phu', dataIndex: 'vung_phu_song', width: 90 },
    """ + extra_col_code + """
    {
      title: 'Hanh dong', width: 100, fixed: 'right' as const,
      render: (_: unknown, r: Cell""" + TU + """) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell """ + TU + """</Typography.Title>
        <Space>
          <Upload beforeUpload={handleImport} accept=".xlsx,.xls" showUploadList={false}>
            <Button icon={<UploadOutlined />}>Import Excel</Button>
          </Upload>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Them moi
          </Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="280px">
          <Input prefix={<SearchOutlined />} placeholder="Tim cell/site..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Vendor" allowClear style={{ width: 130 }}
                  onChange={(v) => setVendor(v)}>
            {vendors.map((v) =>
              <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading}
             size="small" scroll={{ x: 900 }}
             pagination={{ pageSize: 50, showTotal: (t) => `${t} cells` }} />

      <Modal title={editing ? 'Chinh sua Cell' : 'Them Cell moi'}
             open={modalOpen} onOk={handleSave}
             onCancel={() => setModalOpen(false)}
             width={720} okText="Luu">
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: true }]}>
                <Select showSearch optionFilterProp="children"
                  filterOption={(input, option) =>
                    String(option?.children ?? '')
                      .toLowerCase().includes(input.toLowerCase())}>
                  {sites.map((s) =>
                    <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name" label="Site Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="vendor" label="Vendor">
                <Select allowClear>
                  {vendors.map((v) =>
                    <Select.Option key={v} value={v}>{v}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="azimuth" label="Azimuth">
                <InputNumber style={{ width:'100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="do_cao_anten" label="Do cao anten">
                <InputNumber style={{ width:'100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="m_tilt" label="M-Tilt">
                <InputNumber style={{ width:'100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="e_tilt" label="E-Tilt">
                <InputNumber style={{ width:'100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2','4x4','8x8'].map((m) =>
                    <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vung_phu_song" label="Vung phu song">
                <Select allowClear>
                  <Select.Option value="Indoor">Indoor</Select.Option>
                  <Select.Option value="Outdoor">Outdoor</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            """ + extra_form_code + """
          </Row>
        </Form>
      </Modal>
    </div>
  )
}
"""
        write_file(f"{BASE_DIR}/frontend/src/pages/cells/Cells{TU}Page.tsx", content)

    write_cell_page(
        "3g",
        extra_cols=[("PSC", "psc", 80), ("ARFCN", "arfcn", 80)],
        extra_form_items=[("psc", "PSC"), ("arfcn", "ARFCN")],
    )
    write_cell_page(
        "4g",
        extra_cols=[("PCI", "pci", 80), ("EARFCN", "earfcn", 90)],
        extra_form_items=[("pci", "PCI"), ("earfcn", "EARFCN"), ("root_sequence_id", "Root Seq ID")],
    )
    write_cell_page(
        "5g",
        extra_cols=[("PCI", "pci", 80), ("NR-ARFCN", "nr_arfcn", 90)],
        extra_form_items=[("pci", "PCI"), ("nr_arfcn", "NR-ARFCN"), ("root_sequence_id", "Root Seq ID")],
    )

    # ── UsersPage ─────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/pages/admin/UsersPage.tsx", """\
import React, { useEffect, useState } from 'react'
import {
  Typography, Table, Button, Space, Tag, Modal,
  Form, Input, Select, Popconfirm, message, Row,
} from 'antd'
import { PlusOutlined, EditOutlined, DeleteOutlined } from '@ant-design/icons'
import api from '@/api/client'
import type { User } from '@/types'

export default function UsersPage() {
  const [users,   setUsers]   = useState<User[]>([])
  const [loading, setLoading] = useState(false)
  const [modalOpen, setModalOpen] = useState(false)
  const [editing,   setEditing]   = useState<User | null>(null)
  const [form] = Form.useForm()

  const load = () => {
    setLoading(true)
    api.get('/api/v1/users/')
       .then((r) => setUsers(r.data))
       .finally(() => setLoading(false))
  }
  useEffect(load, [])

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (u: User) => { setEditing(u); form.setFieldsValue(u); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) {
        await api.put(`/api/v1/users/${editing.id}`, values)
        message.success('Cap nhat thanh cong')
      } else {
        await api.post('/api/v1/users/', values)
        message.success('Tao user thanh cong')
      }
      setModalOpen(false)
      load()
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Loi')
    }
  }

  const handleDelete = async (id: number) => {
    await api.delete(`/api/v1/users/${id}`)
    message.success('Da xoa')
    load()
  }

  const columns = [
    { title: 'Username', dataIndex: 'username' },
    { title: 'Email',    dataIndex: 'email'    },
    { title: 'Ho ten',   dataIndex: 'full_name' },
    {
      title: 'Role', dataIndex: 'role',
      render: (v: string) =>
        <Tag color={v === 'admin' ? 'red' : 'blue'}>{v.toUpperCase()}</Tag>,
    },
    {
      title: 'Trang thai', dataIndex: 'is_active',
      render: (v: boolean) =>
        <Tag color={v ? 'green' : 'default'}>{v ? 'Active' : 'Inactive'}</Tag>,
    },
    {
      title: 'Provider', dataIndex: 'auth_provider',
      render: (v: string) => <Tag>{v}</Tag>,
    },
    {
      title: 'Hanh dong',
      render: (_: unknown, r: User) => (
        <Space>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xoa user?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Quan ly nguoi dung</Typography.Title>
        <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
          Them user
        </Button>
      </Row>

      <Table columns={columns} dataSource={users} rowKey="id"
             loading={loading} size="small" pagination={{ pageSize: 20 }} />

      <Modal title={editing ? 'Chinh sua user' : 'Them user moi'}
             open={modalOpen} onOk={handleSave}
             onCancel={() => setModalOpen(false)}>
        <Form form={form} layout="vertical">
          <Form.Item name="username" label="Username"
                     rules={[{ required: !editing }]}>
            <Input disabled={Boolean(editing)} />
          </Form.Item>
          <Form.Item name="email" label="Email"
                     rules={[{ required: !editing, type: 'email' }]}>
            <Input />
          </Form.Item>
          <Form.Item name="full_name" label="Ho ten">
            <Input />
          </Form.Item>
          {!editing && (
            <Form.Item name="password" label="Mat khau"
                       rules={[{ required: true }]}>
              <Input.Password />
            </Form.Item>
          )}
          <Form.Item name="role" label="Role">
            <Select>
              <Select.Option value="user">User</Select.Option>
              <Select.Option value="admin">Admin</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="is_active" label="Trang thai">
            <Select>
              <Select.Option value={true}>Active</Select.Option>
              <Select.Option value={false}>Inactive</Select.Option>
            </Select>
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}
""")

    # ── AuditPage ─────────────────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/pages/admin/AuditPage.tsx", """\
import React, { useEffect, useState } from 'react'
import { Typography, Table, Select, Space, Tag, Row, Button } from 'antd'
import { ReloadOutlined } from '@ant-design/icons'
import { getAuditLogs } from '@/api/report'
import type { AuditLog } from '@/types'

const ACTION_COLOR: Record<string, string> = {
  CREATE: 'green', UPDATE: 'blue', DELETE: 'red',
}

export default function AuditPage() {
  const [logs,    setLogs]    = useState<AuditLog[]>([])
  const [loading, setLoading] = useState(false)
  const [action,  setAction]  = useState<string | undefined>()
  const [table,   setTable]   = useState<string | undefined>()

  const load = () => {
    setLoading(true)
    getAuditLogs({ action, table_name: table, limit: 200 })
      .then(setLogs)
      .finally(() => setLoading(false))
  }
  useEffect(load, [action, table])

  const columns = [
    {
      title: 'Thoi gian', dataIndex: 'timestamp', width: 180,
      render: (v: string) => new Date(v).toLocaleString('vi-VN'),
    },
    { title: 'User',      dataIndex: 'username',   width: 120 },
    {
      title: 'Action', dataIndex: 'action', width: 90,
      render: (v: string) =>
        <Tag color={ACTION_COLOR[v] || 'default'}>{v}</Tag>,
    },
    { title: 'Bang',      dataIndex: 'table_name', width: 120 },
    { title: 'Record ID', dataIndex: 'record_id',  width: 90  },
    { title: 'Du lieu cu', dataIndex: 'old_value', ellipsis: true },
    { title: 'Du lieu moi', dataIndex: 'new_value', ellipsis: true },
  ]

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Audit Log</Typography.Title>
        <Button icon={<ReloadOutlined />} onClick={load}>Lam moi</Button>
      </Row>

      <Space style={{ marginBottom: 12 }}>
        <Select placeholder="Action" allowClear style={{ width: 120 }}
                onChange={setAction}>
          {['CREATE','UPDATE','DELETE'].map((a) =>
            <Select.Option key={a} value={a}>{a}</Select.Option>)}
        </Select>
        <Select placeholder="Bang du lieu" allowClear style={{ width: 160 }}
                onChange={setTable}>
          {['sites','cells_3g','cells_4g','cells_5g'].map((t) =>
            <Select.Option key={t} value={t}>{t}</Select.Option>)}
        </Select>
      </Space>

      <Table columns={columns} dataSource={logs} rowKey="id"
             loading={loading} size="small"
             pagination={{ pageSize: 50, showTotal: (t) => `${t} records` }} />
    </div>
  )
}
""")

    # ── Dropdowns placeholder ─────────────────────────────────────────
    write_file(f"{BASE_DIR}/frontend/src/pages/dropdowns/DropdownsPage.tsx", """\
import React from 'react'
import { Typography } from 'antd'
export default function DropdownsPage() {
  return <Typography.Title level={3}>Quan ly danh muc (coming soon)</Typography.Title>
}
""")

    # ================================================================== #
    #  UTILITY SCRIPTS
    # ================================================================== #
    write_file(f"{BASE_DIR}/start.sh", """\
#!/bin/bash
set -e
echo "Starting SiteLink..."
docker compose up -d --build
echo ""
echo "SiteLink is running!"
echo "  Frontend : http://localhost"
echo "  API docs : http://localhost/api/docs"
echo "  Login    : admin / admin"
""")
    os.chmod(f"{BASE_DIR}/start.sh", 0o755)

    write_file(f"{BASE_DIR}/stop.sh", """\
#!/bin/bash
docker compose down
""")
    os.chmod(f"{BASE_DIR}/stop.sh", 0o755)

    write_file(f"{BASE_DIR}/reset_db.sh", """\
#!/bin/bash
echo "WARNING: This will DELETE all data!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read
docker compose down -v
docker compose up -d --build
echo "Database reset complete."
""")
    os.chmod(f"{BASE_DIR}/reset_db.sh", 0o755)

    # ── README (stored in variable to avoid backtick parsing issues) ──
    readme = (
        "# SiteLink - He thong quan ly du lieu toi uu\n\n"
        "## Quick Start\n\n"
        "    cd /home/mlmt/work/src/SiteLink\n"
        "    ./start.sh\n\n"
        "Open http://localhost and login with admin / admin\n\n"
        "## Development (without Docker)\n\n"
        "### Backend\n\n"
        "    cd backend\n"
        "    pip install -r requirements.txt\n"
        "    # Edit .env: set POSTGRES_HOST=localhost\n"
        "    uvicorn app.main:app --reload --port 8000\n\n"
        "### Frontend\n\n"
        "    cd frontend\n"
        "    npm install\n"
        "    npm run dev\n\n"
        "## Tech Stack\n\n"
        "- Backend  : FastAPI + SQLAlchemy + PostgreSQL\n"
        "- Frontend : React 18 + TypeScript + Ant Design + Vite\n"
        "- Database : PostgreSQL 15 (Docker volume)\n"
        "- Auth     : JWT local + SSO-ready placeholders\n\n"
        "## API Documentation\n\n"
        "- Swagger UI : http://localhost/api/docs\n"
        "- ReDoc      : http://localhost/api/redoc\n\n"
        "## Default Credentials\n\n"
        "  Username : admin\n"
        "  Password : admin\n"
        "  Role     : Admin\n\n"
        "## SSO Integration (Future)\n\n"
        "The auth system is pre-wired for SSO:\n"
        "- User.auth_provider field : local | sso\n"
        "- User.sso_subject for SSO sub claim\n"
        "- /api/v1/auth/sso/login + /api/v1/auth/sso/callback placeholder routes\n"
        "- get_or_create_sso_user() in app/services/auth.py\n\n"
        "To enable SSO: fill SSO_CLIENT_ID, SSO_CLIENT_SECRET, SSO_AUTHORITY in .env\n"
        "and implement the OAuth2 flow in app/api/routes/auth.py.\n\n"
        "## Data Import via Excel\n\n"
        "- Sites   : POST /api/v1/sites/import-excel\n"
        "- Cells3G : POST /api/v1/cells-3g/import-excel\n"
        "- Cells4G : POST /api/v1/cells-4g/import-excel\n"
        "- Cells5G : POST /api/v1/cells-5g/import-excel\n\n"
        "Excel columns must match the field names defined in import_excel.py.\n\n"
        "## Project Structure\n\n"
        "  SiteLink/\n"
        "  backend/\n"
        "    app/\n"
        "      api/routes/   <- FastAPI routers\n"
        "      core/         <- Config, security\n"
        "      db/           <- SQLAlchemy session, base\n"
        "      models/       <- ORM models\n"
        "      schemas/      <- Pydantic schemas\n"
        "      services/     <- Business logic\n"
        "      utils/        <- Deps, audit helpers\n"
        "    requirements.txt\n"
        "  frontend/\n"
        "    src/\n"
        "      api/          <- Axios API calls\n"
        "      components/   <- Layout, shared UI\n"
        "      pages/        <- Route pages\n"
        "      store/        <- Zustand state\n"
        "      types/        <- TypeScript interfaces\n"
        "  nginx/nginx.conf\n"
        "  docker-compose.yml\n"
        "  .env\n"
    )
    write_file(f"{BASE_DIR}/README.md", readme)

    # ================================================================== #
    print("\n" + "=" * 60)
    print("  Setup complete!")
    print("=" * 60)
    print(f"\n  Project : {BASE_DIR}")
    print("\n  To start:")
    print("    cd /home/mlmt/work/src/SiteLink")
    print("    ./start.sh")
    print("\n  Dev mode (no Docker):")
    print("    Backend  : cd backend && pip install -r requirements.txt")
    print("               uvicorn app.main:app --reload")
    print("    Frontend : cd frontend && npm install && npm run dev")
    print("\n  URL      : http://localhost")
    print("  Login    : admin / admin")
    print("  API docs : http://localhost/api/docs")
    print("=" * 60)


if __name__ == "__main__":
    setup()