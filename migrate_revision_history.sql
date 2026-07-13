-- ============================================================
-- SiteLink DB Migration: Revision History
-- ============================================================

-- Site revisions table
CREATE TABLE IF NOT EXISTS site_revisions (
    id              SERIAL PRIMARY KEY,
    site_id         INTEGER NOT NULL,          -- logical ID (from sites table)
    site_name       VARCHAR(100) NOT NULL,     -- site_name AT THIS REVISION
    revision_no     INTEGER NOT NULL DEFAULT 1,
    changed_by      INTEGER REFERENCES users(id) ON DELETE SET NULL,
    changed_by_name VARCHAR(100),
    change_source   VARCHAR(20) DEFAULT 'form', -- 'form' | 'excel'
    change_note     TEXT,

    -- snapshot of ALL site fields at this revision
    mien                    VARCHAR(10),
    tinh                    VARCHAR(100),
    phuong_xa               VARCHAR(150),
    site_name_cu            VARCHAR(100),
    site_name_old_ref       VARCHAR(100),      -- previous site_name before rename
    site_vip                VARCHAR(10),
    lat                     FLOAT,
    long                    FLOAT,
    tram_2g                 BOOLEAN DEFAULT FALSE,
    tram_3g                 BOOLEAN DEFAULT FALSE,
    tram_4g                 BOOLEAN DEFAULT FALSE,
    tram_5g                 BOOLEAN DEFAULT FALSE,
    repeater                BOOLEAN DEFAULT FALSE,
    booster                 BOOLEAN DEFAULT FALSE,
    node_truyen_dan_only    BOOLEAN DEFAULT FALSE,
    tram_phu_song_tsca      BOOLEAN DEFAULT FALSE,
    phan_loai_tram          VARCHAR(100),
    moran_3g                VARCHAR(50),
    moran_4g                VARCHAR(50),
    moran_5g                VARCHAR(50),
    ma_ptm                  VARCHAR(100),
    do_cao_dinh_cot_anten   FLOAT,
    do_cao_cot_anten        FLOAT,
    dia_chi                 TEXT,
    ghi_chu                 TEXT,

    -- what changed (JSON diff)
    changed_fields          TEXT,              -- JSON: {field: [old, new]}
    created_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_site_rev_site_id   ON site_revisions(site_id);
CREATE INDEX IF NOT EXISTS idx_site_rev_site_name ON site_revisions(site_name);
CREATE INDEX IF NOT EXISTS idx_site_rev_created   ON site_revisions(created_at DESC);

-- Cell 3G revisions
CREATE TABLE IF NOT EXISTS cell_3g_revisions (
    id              SERIAL PRIMARY KEY,
    cell_id_ref     INTEGER NOT NULL,          -- FK to cells_3g.id
    site_id         INTEGER NOT NULL,
    site_name       VARCHAR(100) NOT NULL,
    cell_name       VARCHAR(100) NOT NULL,     -- cell_name AT THIS REVISION
    revision_no     INTEGER NOT NULL DEFAULT 1,
    changed_by      INTEGER REFERENCES users(id) ON DELETE SET NULL,
    changed_by_name VARCHAR(100),
    change_source   VARCHAR(20) DEFAULT 'form',
    change_note     TEXT,

    -- snapshot
    mien            VARCHAR(10),
    tinh            VARCHAR(100),
    phuong_xa       VARCHAR(150),
    site_name_old   VARCHAR(100),
    cell_name_old   VARCHAR(100),
    cell_vip        VARCHAR(10),
    moran           VARCHAR(50),
    lat             FLOAT,
    long            FLOAT,
    vung_phu_song   VARCHAR(20),
    vendor          VARCHAR(50),
    do_cao_anten    FLOAT,
    azimuth         FLOAT,
    m_tilt          FLOAT,
    e_tilt          FLOAT,
    total_tilt      FLOAT,
    loai_anten      VARCHAR(200),
    chung_anten     VARCHAR(100),
    baseband        VARCHAR(100),
    rf              VARCHAR(100),
    cell_id         VARCHAR(50),
    arfcn           VARCHAR(50),
    psc             VARCHAR(50),
    mimo            VARCHAR(20),

    changed_fields  TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cell3g_rev_cell_id   ON cell_3g_revisions(cell_id_ref);
CREATE INDEX IF NOT EXISTS idx_cell3g_rev_site_name ON cell_3g_revisions(site_name);
CREATE INDEX IF NOT EXISTS idx_cell3g_rev_cell_name ON cell_3g_revisions(cell_name);
CREATE INDEX IF NOT EXISTS idx_cell3g_rev_created   ON cell_3g_revisions(created_at DESC);

-- Cell 4G revisions
CREATE TABLE IF NOT EXISTS cell_4g_revisions (
    id              SERIAL PRIMARY KEY,
    cell_id_ref     INTEGER NOT NULL,
    site_id         INTEGER NOT NULL,
    site_name       VARCHAR(100) NOT NULL,
    cell_name       VARCHAR(100) NOT NULL,
    revision_no     INTEGER NOT NULL DEFAULT 1,
    changed_by      INTEGER REFERENCES users(id) ON DELETE SET NULL,
    changed_by_name VARCHAR(100),
    change_source   VARCHAR(20) DEFAULT 'form',
    change_note     TEXT,

    mien            VARCHAR(10),
    tinh            VARCHAR(100),
    phuong_xa       VARCHAR(150),
    site_name_old   VARCHAR(100),
    cell_name_old   VARCHAR(100),
    cell_vip        VARCHAR(10),
    moran           VARCHAR(50),
    lat             FLOAT,
    long            FLOAT,
    vung_phu_song   VARCHAR(20),
    vendor          VARCHAR(50),
    do_cao_anten    FLOAT,
    azimuth         FLOAT,
    m_tilt          FLOAT,
    e_tilt          FLOAT,
    total_tilt      FLOAT,
    loai_anten      VARCHAR(200),
    chung_anten     VARCHAR(100),
    baseband        VARCHAR(100),
    rf              VARCHAR(100),
    cell_id         VARCHAR(50),
    earfcn          VARCHAR(50),
    pci             VARCHAR(50),
    root_sequence_id VARCHAR(50),
    mimo            VARCHAR(20),

    changed_fields  TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cell4g_rev_cell_id   ON cell_4g_revisions(cell_id_ref);
CREATE INDEX IF NOT EXISTS idx_cell4g_rev_site_name ON cell_4g_revisions(site_name);
CREATE INDEX IF NOT EXISTS idx_cell4g_rev_cell_name ON cell_4g_revisions(cell_name);
CREATE INDEX IF NOT EXISTS idx_cell4g_rev_created   ON cell_4g_revisions(created_at DESC);

-- Cell 5G revisions
CREATE TABLE IF NOT EXISTS cell_5g_revisions (
    id              SERIAL PRIMARY KEY,
    cell_id_ref     INTEGER NOT NULL,
    site_id         INTEGER NOT NULL,
    site_name       VARCHAR(100) NOT NULL,
    cell_name       VARCHAR(100) NOT NULL,
    revision_no     INTEGER NOT NULL DEFAULT 1,
    changed_by      INTEGER REFERENCES users(id) ON DELETE SET NULL,
    changed_by_name VARCHAR(100),
    change_source   VARCHAR(20) DEFAULT 'form',
    change_note     TEXT,

    mien            VARCHAR(10),
    tinh            VARCHAR(100),
    phuong_xa       VARCHAR(150),
    site_name_old   VARCHAR(100),
    cell_name_old   VARCHAR(100),
    cell_vip        VARCHAR(10),
    moran           VARCHAR(50),
    lat             FLOAT,
    long            FLOAT,
    vung_phu_song   VARCHAR(20),
    vendor          VARCHAR(50),
    do_cao_anten    FLOAT,
    azimuth         FLOAT,
    m_tilt          FLOAT,
    e_tilt          FLOAT,
    total_tilt      FLOAT,
    loai_anten      VARCHAR(200),
    baseband        VARCHAR(100),
    rf              VARCHAR(100),
    cell_id         VARCHAR(50),
    nr_arfcn        VARCHAR(50),
    pci             VARCHAR(50),
    root_sequence_id VARCHAR(50),
    mimo            VARCHAR(20),

    changed_fields  TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cell5g_rev_cell_id   ON cell_5g_revisions(cell_id_ref);
CREATE INDEX IF NOT EXISTS idx_cell5g_rev_site_name ON cell_5g_revisions(site_name);
CREATE INDEX IF NOT EXISTS idx_cell5g_rev_cell_name ON cell_5g_revisions(cell_name);
CREATE INDEX IF NOT EXISTS idx_cell5g_rev_created   ON cell_5g_revisions(created_at DESC);

SELECT 'Revision history migration completed.' AS result;
