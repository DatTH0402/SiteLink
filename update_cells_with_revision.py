"""
update_cells_with_revision.py (project root) - thin wrapper.

The real logic lives in backend/update_cells_with_revision.py + backend/cell_sync_core.py
so the manual daily run and the web app can never drift apart.

    python update_cells_with_revision.py [--dry-run] [--tech 3g,4g,5g]
"""
import os
import runpy
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.join(HERE, "backend")
sys.path.insert(0, BACKEND)
runpy.run_path(os.path.join(BACKEND, "update_cells_with_revision.py"), run_name="__main__")
