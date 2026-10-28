-- RydAR curve table, as shipped in ios/RydAR/curves.sqlite. The app recomputes warning speeds.
-- Do not add screening_mph columns. e and f live in the app, not in this file.

CREATE TABLE curves (
  id TEXT PRIMARY KEY,
  county TEXT NOT NULL,
  road_name TEXT,
  surface TEXT NOT NULL,          -- paved | unpaved, as labeled by the GIS file
  radius_ft REAL NOT NULL,
  deflection_deg REAL,
  length_m REAL,
  rd_class TEXT,
  rd_design TEXT,
  turn_dir TEXT,
  closed_loop INTEGER NOT NULL DEFAULT 0,
  quality_flags TEXT NOT NULL DEFAULT '',
  osm_maxspeed TEXT,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  min_lat REAL NOT NULL,
  max_lat REAL NOT NULL,
  min_lon REAL NOT NULL,
  max_lon REAL NOT NULL,
  coordinates_json TEXT NOT NULL  -- [[lon, lat], ...] from the GeoJSON line
);

CREATE INDEX curves_bbox ON curves (min_lat, max_lat, min_lon, max_lon);
CREATE INDEX curves_county_class ON curves (county, rd_class);

-- Everything below stays on the phone. The app creates these tables (PassLog.swift), not the importer.
CREATE TABLE trips (
  id TEXT PRIMARY KEY,
  started_at TEXT NOT NULL,
  driver_mode TEXT NOT NULL,      -- adult | under18 (older rows may say passenger; the app reads them as adult)
  notes TEXT
);

CREATE TABLE trip_passes (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL,
  curve_id TEXT NOT NULL,
  direction TEXT,
  v_eff_mph REAL,
  v_lo_mph REAL,
  v_hi_mph REAL,
  spoke INTEGER NOT NULL DEFAULT 0,
  hour_bucket INTEGER,
  late INTEGER NOT NULL DEFAULT 0,
  surface_used TEXT,
  radius_band TEXT,
  look_ahead_m REAL,
  braking_m REAL,
  FOREIGN KEY (trip_id) REFERENCES trips (id)
);

-- On-device timing memory. Counts and summed braking distances only.
-- The prior of two late and two early passes is applied in code, not stored as rows.
CREATE TABLE approach_memory (
  context_key TEXT PRIMARY KEY,
  late_passes INTEGER NOT NULL DEFAULT 0,
  early_passes INTEGER NOT NULL DEFAULT 0,
  onset_count INTEGER NOT NULL DEFAULT 0,
  onset_sum_m REAL NOT NULL DEFAULT 0
);

CREATE TABLE curve_memory (
  curve_id TEXT PRIMARY KEY,
  late_passes INTEGER NOT NULL DEFAULT 0,
  early_passes INTEGER NOT NULL DEFAULT 0,
  onset_count INTEGER NOT NULL DEFAULT 0,
  onset_sum_m REAL NOT NULL DEFAULT 0
);

-- The small on-device network that places a warning from where this phone brakes.
CREATE TABLE onset_net (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  sample_count INTEGER NOT NULL,
  weights TEXT NOT NULL,
  bias TEXT NOT NULL
);
