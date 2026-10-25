-- CurveAudit curve table. The app recomputes warning speeds.
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

-- Trips stay on the phone. This table is created by the app, not by the importer.
CREATE TABLE trips (
  id TEXT PRIMARY KEY,
  started_at TEXT NOT NULL,
  driver_mode TEXT NOT NULL,      -- adult | passenger | under18
  notes TEXT
);

CREATE TABLE trip_passes (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL,
  curve_id TEXT NOT NULL,
  v_eff_mph REAL,
  v_lo_mph REAL,
  v_hi_mph REAL,
  spoke INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (trip_id) REFERENCES trips (id)
);
