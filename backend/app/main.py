from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db.session import engine, SessionLocal
from app.db import base  # noqa – registers all models
from app.db.base import Base
from app.api.routes import (
    auth, users, sites, cells_3g, cells_4g, cells_5g,
    dropdowns, report, audit,
)
from app.api.routes import antenna as antenna_router
from app.api.routes import templates as templates_router

Base.metadata.create_all(bind=engine)


def _seed_initial_data():
    db = SessionLocal()
    try:
        from app.models.user import User, UserRole
        from app.core.security import get_password_hash
        from app.models.dropdown import DropdownGeneral, DropdownVendor

        if not db.query(User).filter(User.username == "admin").first():
            db.add(User(
                email="admin@sitelink.com",
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


def _generate_templates():
    """Generate Excel templates on startup if they don't exist."""
    import os, sys
    template_dir = os.path.join(
        os.path.dirname(__file__), "..", "templates"
    )
    template_dir = os.path.abspath(template_dir)
    os.makedirs(template_dir, exist_ok=True)

    required = [
        "template_site.xlsx",
        "template_cell_3g.xlsx",
        "template_cell_4g.xlsx",
        "template_cell_5g.xlsx",
    ]
    missing = [f for f in required
               if not os.path.exists(os.path.join(template_dir, f))]

    if missing:
        try:
            script = os.path.join(
                os.path.dirname(__file__), "..", "create_templates.py"
            )
            if os.path.exists(script):
                import importlib.util
                spec = importlib.util.spec_from_file_location(
                    "create_templates", script
                )
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                mod.create_site_template()
                mod.create_cell3g_template()
                mod.create_cell4g_template()
                mod.create_cell5g_template()
                print("[startup] Excel templates generated.")
        except Exception as exc:
            print(f"[startup] Warning: could not generate templates: {exc}")


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
    _generate_templates()


PREFIX = "/api/v1"
app.include_router(auth.router,             prefix=f"{PREFIX}/auth",       tags=["Auth"])
app.include_router(users.router,            prefix=f"{PREFIX}/users",      tags=["Users"])
app.include_router(sites.router,            prefix=f"{PREFIX}/sites",      tags=["Sites"])
app.include_router(cells_3g.router,         prefix=f"{PREFIX}/cells-3g",   tags=["Cells-3G"])
app.include_router(cells_4g.router,         prefix=f"{PREFIX}/cells-4g",   tags=["Cells-4G"])
app.include_router(cells_5g.router,         prefix=f"{PREFIX}/cells-5g",   tags=["Cells-5G"])
app.include_router(dropdowns.router,        prefix=f"{PREFIX}/dropdowns",  tags=["Dropdowns"])
app.include_router(report.router,           prefix=f"{PREFIX}/report",     tags=["Report"])
app.include_router(audit.router,            prefix=f"{PREFIX}/audit",      tags=["Audit"])
app.include_router(antenna_router.router,   prefix=f"{PREFIX}/antennas",   tags=["Antennas"])
app.include_router(templates_router.router, prefix=f"{PREFIX}/templates",  tags=["Templates"])


@app.get("/health")
def health():
    return {"status": "ok"}
