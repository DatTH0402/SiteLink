from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


# Import all models so SQLAlchemy registers them
from app.models import (  # noqa
    user, site, cell_3g, cell_4g, cell_5g,
    dropdown, audit_log
)
