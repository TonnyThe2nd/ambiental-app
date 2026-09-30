-- Área de impacto das ocorrências (raio em que a pessoa está "dentro" do risco).
-- Espelha incidents/domain/impact.py. Idempotente.
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS impact_radius_m INTEGER;

UPDATE incidents
   SET impact_radius_m = LEAST(5000, GREATEST(50, round(
         (CASE lower(category)
      WHEN 'alagamento' THEN 400
      WHEN 'poluicao' THEN 1500
      WHEN 'queimada' THEN 2000
      WHEN 'incendio' THEN 1500
      WHEN 'desmatamento' THEN 1000
      WHEN 'esgoto' THEN 200
      WHEN 'lixo' THEN 150
      WHEN 'ruido' THEN 300
      WHEN 'erosao' THEN 300
      WHEN 'arvore_caida' THEN 100
      WHEN 'animal_morto' THEN 100
      WHEN 'outro' THEN 250
            ELSE 250 END)
         * (CASE severity::text WHEN 'leve' THEN 0.75 WHEN 'critico' THEN 1.5 ELSE 1.0 END)
         / 10.0) * 10))::int
 WHERE impact_radius_m IS NULL;

DO $$ BEGIN
  ALTER TABLE incidents ADD CONSTRAINT incidents_impact_radius_range
    CHECK (impact_radius_m IS NULL OR impact_radius_m BETWEEN 50 AND 5000);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
