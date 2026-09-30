-- Particionamento geoespacial (GeoHash) e armazenamento das fotos dos relatos.
-- Idempotente: é reaplicada a cada deploy.

-- 1) GeoHash de precisão 7 (~150 m) em cada ocorrência. Os prefixos definem as
--    partições usadas no tempo real (precisão 4), no cache e no mapa de calor (3 a 7).
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS geohash VARCHAR(12);

UPDATE incidents
   SET geohash = ST_GeoHash(ST_SetSRID(ST_MakePoint(longitude, latitude), 4326), 7)
 WHERE geohash IS NULL;

-- text_pattern_ops permite que "geohash LIKE '6gyf%'" use o índice (busca por prefixo).
CREATE INDEX IF NOT EXISTS incidents_geohash_prefix_idx
  ON incidents (geohash text_pattern_ops);

-- 2) Fotos dos relatos. Antes, o app guardava a foto só no aparelho e o servidor
--    recebia image_url nulo. Guardar no PostgreSQL evita depender de disco local
--    do contêiner (efêmero no Render) e mantém a foto na mesma política de backup.
CREATE TABLE IF NOT EXISTS incident_photos (
  incident_id UUID PRIMARY KEY REFERENCES incidents(id) ON DELETE CASCADE,
  content BYTEA NOT NULL,
  content_type VARCHAR(40) NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp')),
  size_bytes INTEGER NOT NULL CHECK (size_bytes BETWEEN 1 AND 5242880),
  uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
