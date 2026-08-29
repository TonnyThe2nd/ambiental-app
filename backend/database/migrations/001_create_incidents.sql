CREATE TABLE IF NOT EXISTS incidents (
  id UUID PRIMARY KEY,
  category VARCHAR(100) NOT NULL CHECK (char_length(trim(category)) > 0),
  latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  occurred_at TIMESTAMPTZ NOT NULL,
  image_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS incidents_occurred_at_idx
  ON incidents (occurred_at DESC);
