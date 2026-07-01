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
