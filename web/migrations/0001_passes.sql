CREATE TABLE IF NOT EXISTS passes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  curve_id TEXT NOT NULL,
  direction TEXT NOT NULL,
  speed_band_mph INTEGER NOT NULL,
  hour_bucket INTEGER NOT NULL,
  app_version TEXT NOT NULL,
  lat_accel_band INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS passes_curve ON passes (curve_id);
