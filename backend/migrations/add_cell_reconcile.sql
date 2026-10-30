-- Plain-SQL alternative to: python reconcile_cells.py --init-db
CREATE TABLE IF NOT EXISTS cell_reconcile_runs (
    id SERIAL PRIMARY KEY, batch_id VARCHAR(40), tech VARCHAR(5) NOT NULL, run_date VARCHAR(10),
    started_at TIMESTAMPTZ, finished_at TIMESTAMPTZ, status VARCHAR(20) NOT NULL DEFAULT 'ok',
    error TEXT, prev_run_id INTEGER,
    dump_total INTEGER DEFAULT 0, dump_active INTEGER DEFAULT 0, dump_inactive INTEGER DEFAULT 0,
    web_total INTEGER DEFAULT 0, matched INTEGER DEFAULT 0,
    missing_in_web INTEGER DEFAULT 0, missing_in_dump INTEGER DEFAULT 0,
    missing_in_dump_uncovered INTEGER DEFAULT 0, dump_inactive_not_in_web INTEGER DEFAULT 0,
    new_missing_in_web INTEGER DEFAULT 0, new_missing_in_dump INTEGER DEFAULT 0,
    resolved_missing_in_web INTEGER DEFAULT 0, resolved_missing_in_dump INTEGER DEFAULT 0,
    vendor_status TEXT, status_stats TEXT
);
CREATE INDEX IF NOT EXISTS ix_cell_reconcile_runs_tech_id ON cell_reconcile_runs (tech, id);
CREATE TABLE IF NOT EXISTS cell_reconcile_items (
    id SERIAL PRIMARY KEY, run_id INTEGER NOT NULL, tech VARCHAR(5) NOT NULL, direction VARCHAR(20) NOT NULL,
    cell_name VARCHAR(200), subcell_id VARCHAR(50), web_id INTEGER, site_name VARCHAR(200), vendor VARCHAR(50),
    mien VARCHAR(10), tinh VARCHAR(100), phuong_xa VARCHAR(150), cell_status VARCHAR(100),
    bbu_name VARCHAR(200), rf VARCHAR(200), oss VARCHAR(50), dump_date VARCHAR(50), cell_id VARCHAR(50),
    node_id VARCHAR(50), freq VARCHAR(50), pci VARCHAR(50), tac VARCHAR(50), bandwidth VARCHAR(50),
    mimo VARCHAR(100), web_updated_at VARCHAR(30), first_seen VARCHAR(10), dump_covered VARCHAR(1)
);
CREATE INDEX IF NOT EXISTS ix_cell_reconcile_items_run_dir ON cell_reconcile_items (run_id, direction);
