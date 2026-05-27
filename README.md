# SiteLink - He thong quan ly du lieu toi uu

## Quick Start

    cd /home/mlmt/work/src/SiteLink
    ./start.sh

Open http://localhost and login with admin / admin

## Development (without Docker)

### Backend

    cd backend
    pip install -r requirements.txt
    # Edit .env: set POSTGRES_HOST=localhost
    uvicorn app.main:app --reload --port 8000

### Frontend

    cd frontend
    npm install
    npm run dev

## Tech Stack

- Backend  : FastAPI + SQLAlchemy + PostgreSQL
- Frontend : React 18 + TypeScript + Ant Design + Vite
- Database : PostgreSQL 15 (Docker volume)
- Auth     : JWT local + SSO-ready placeholders

## API Documentation

- Swagger UI : http://localhost/api/docs
- ReDoc      : http://localhost/api/redoc

## Default Credentials

  Username : admin
  Password : admin
  Role     : Admin

## SSO Integration (Future)

The auth system is pre-wired for SSO:
- User.auth_provider field : local | sso
- User.sso_subject for SSO sub claim
- /api/v1/auth/sso/login + /api/v1/auth/sso/callback placeholder routes
- get_or_create_sso_user() in app/services/auth.py

To enable SSO: fill SSO_CLIENT_ID, SSO_CLIENT_SECRET, SSO_AUTHORITY in .env
and implement the OAuth2 flow in app/api/routes/auth.py.

## Data Import via Excel

- Sites   : POST /api/v1/sites/import-excel
- Cells3G : POST /api/v1/cells-3g/import-excel
- Cells4G : POST /api/v1/cells-4g/import-excel
- Cells5G : POST /api/v1/cells-5g/import-excel

Excel columns must match the field names defined in import_excel.py.

## Project Structure

  SiteLink/
  backend/
    app/
      api/routes/   <- FastAPI routers
      core/         <- Config, security
      db/           <- SQLAlchemy session, base
      models/       <- ORM models
      schemas/      <- Pydantic schemas
      services/     <- Business logic
      utils/        <- Deps, audit helpers
    requirements.txt
  frontend/
    src/
      api/          <- Axios API calls
      components/   <- Layout, shared UI
      pages/        <- Route pages
      store/        <- Zustand state
      types/        <- TypeScript interfaces
  nginx/nginx.conf
  docker-compose.yml
  .env
