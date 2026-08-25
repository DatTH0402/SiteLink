"""
template_regen.py
-----------------
Background template regeneration utility.

Call `schedule_template_regen()` from any route that mutates data used
in Excel templates (antennas, RNC names, dropdown_general, etc.).

The regeneration runs in a daemon thread so it never blocks the API
response. A debounce timer coalesces rapid successive changes into
one single regeneration run.

DB connection: injects DATABASE_URL from the backend's own settings
into the environment before loading create_excel_templates.py, so the
script always uses the same DB the backend is already connected to.
"""
from __future__ import annotations

import importlib.util
import os
import threading
import logging

logger = logging.getLogger(__name__)

# --------------------------------------------------------------------------- #
# Internal state
# --------------------------------------------------------------------------- #
_regen_lock  = threading.Lock()
_regen_timer: threading.Timer | None = None
_DEBOUNCE_SECONDS = 3.0


# --------------------------------------------------------------------------- #
# Path resolution
# --------------------------------------------------------------------------- #

def _find_script() -> str | None:
    """
    Walk UP from this file's directory until create_excel_templates.py
    is found. Works in both Docker and local dev environments.

    Docker  (WORKDIR=/app, ./backend mounted to /app):
      This file : /app/app/utils/template_regen.py
      Script at : /app/create_excel_templates.py   (2 levels up)

    Local dev:
      This file : <project>/backend/app/utils/template_regen.py
      Script at : <project>/create_excel_templates.py  (3 levels up)
                  OR <project>/backend/create_excel_templates.py (2 levels up)
    """
    target  = "create_excel_templates.py"
    current = os.path.dirname(os.path.abspath(__file__))

    for _ in range(6):
        candidate = os.path.join(current, target)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(current)
        if parent == current:
            break
        current = parent
    return None


def _find_template_dir() -> str:
    """
    Resolve backend/templates/ output directory.

    Docker : /app/templates/
    Local  : <project>/backend/templates/
    """
    script = _find_script()
    if script:
        script_dir = os.path.dirname(script)

        # Docker: script is at /app/ → templates at /app/templates/
        candidate = os.path.join(script_dir, "templates")
        if os.path.isdir(candidate):
            return candidate

        # Local dev: script at project root → templates at backend/templates/
        candidate2 = os.path.join(script_dir, "backend", "templates")
        if os.path.isdir(candidate2):
            return candidate2

        # Neither exists yet – create next to script (Docker case)
        os.makedirs(candidate, exist_ok=True)
        return candidate

    fallback = "/app/templates"
    os.makedirs(fallback, exist_ok=True)
    return fallback


def _get_database_url() -> str:
    """
    Return the DATABASE_URL from the backend's own settings.
    This is guaranteed to be correct since the backend is already running.
    """
    try:
        from app.core.config import settings
        return settings.DATABASE_URL
    except Exception as exc:
        logger.warning(
            "[template_regen] Could not import backend settings: %s. "
            "Falling back to env vars.", exc
        )
        # Build manually from POSTGRES_* env vars
        host     = os.getenv("POSTGRES_HOST",     "postgres")
        port     = os.getenv("POSTGRES_PORT",     "5432")
        db       = os.getenv("POSTGRES_DB",       "sitelink_db")
        user     = os.getenv("POSTGRES_USER",     "sitelink")
        password = os.getenv("POSTGRES_PASSWORD", "sitelink_pass")
        return f"postgresql://{user}:{password}@{host}:{port}/{db}"


# --------------------------------------------------------------------------- #
# Core regeneration
# --------------------------------------------------------------------------- #

def _do_regen() -> None:
    """Runs in a background thread."""
    with _regen_lock:
        script_path  = _find_script()
        template_dir = _find_template_dir()

        if not script_path:
            logger.error(
                "[template_regen] create_excel_templates.py not found "
                "anywhere above %s. "
                "Ensure it is copied into backend/ for Docker.",
                os.path.abspath(__file__),
            )
            return

        db_url = _get_database_url()

        logger.info(
            "[template_regen] Starting regeneration ...\n"
            "  script      : %s\n"
            "  output dir  : %s\n"
            "  db host     : %s",
            script_path,
            template_dir,
            db_url.split("@")[-1] if "@" in db_url else "unknown",
        )

        # Save original env vars so we can restore them after the run
        _orig_env = {
            k: os.environ.get(k)
            for k in (
                "DATABASE_URL",
                "POSTGRES_HOST", "POSTGRES_PORT",
                "POSTGRES_DB",   "POSTGRES_USER", "POSTGRES_PASSWORD",
                "SITELINK_TEMPLATE_DIR",
            )
        }

        try:
            os.makedirs(template_dir, exist_ok=True)

            # ── Inject DB credentials ──────────────────────────────────────
            # Set DATABASE_URL so the script's _build_db_params() picks it up.
            # Also set individual POSTGRES_* vars as belt-and-suspenders.
            import urllib.parse as _up
            _p = _up.urlparse(db_url)

            os.environ["DATABASE_URL"]        = db_url
            os.environ["POSTGRES_HOST"]       = _p.hostname or "postgres"
            os.environ["POSTGRES_PORT"]       = str(_p.port or 5432)
            os.environ["POSTGRES_DB"]         = (_p.path or "/sitelink_db").lstrip("/")
            os.environ["POSTGRES_USER"]       = _p.username or "sitelink"
            os.environ["POSTGRES_PASSWORD"]   = _p.password or "sitelink_pass"
            os.environ["SITELINK_TEMPLATE_DIR"] = template_dir

            # ── Load and run the script ────────────────────────────────────
            spec = importlib.util.spec_from_file_location(
                # Use unique name each time to force re-execution
                # (importlib caches by name; a new name bypasses the cache)
                f"create_excel_templates_{threading.get_ident()}",
                script_path,
            )
            mod = importlib.util.module_from_spec(spec)   # type: ignore[arg-type]
            spec.loader.exec_module(mod)                   # type: ignore[union-attr]

            # Force correct output dir even if module computed its own
            mod.OUTPUT_DIR = template_dir
            os.makedirs(template_dir, exist_ok=True)

            mod.create_site_template()
            mod.create_cell3g_template()
            mod.create_cell4g_template()
            mod.create_cell5g_template()
            mod.create_antenna_template()

            logger.info(
                "[template_regen] ✓ All 5 templates regenerated → %s",
                template_dir,
            )

        except Exception:
            logger.exception("[template_regen] Template regeneration failed.")

        finally:
            # ── Restore original env vars ──────────────────────────────────
            for k, v in _orig_env.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v


# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #

def schedule_template_regen(delay: float = _DEBOUNCE_SECONDS) -> None:
    """
    Schedule a template regeneration after `delay` seconds.
    Multiple calls within the debounce window are coalesced into one run.
    """
    global _regen_timer

    if _regen_timer is not None and _regen_timer.is_alive():
        _regen_timer.cancel()

    _regen_timer = threading.Timer(delay, _do_regen)
    _regen_timer.daemon = True
    _regen_timer.name   = "TemplateRegenThread"
    _regen_timer.start()
    logger.info(
        "[template_regen] Regeneration scheduled in %.1f s.", delay
    )


def regen_now() -> None:
    """
    Trigger an immediate regeneration in a background thread.
    Used at application startup.
    """
    t = threading.Thread(
        target=_do_regen,
        daemon=True,
        name="TemplateRegenThread",
    )
    t.start()
