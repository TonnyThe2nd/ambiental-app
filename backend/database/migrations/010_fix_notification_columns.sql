-- A migração 007 tentou alterar estas colunas com ADD COLUMN IF NOT EXISTS.
-- Como a 006 já as havia criado, o PostgreSQL ignorou tipo e padrão desejados.
-- ALTER COLUMN aplica a correção também nos bancos que já executaram as migrações anteriores.
ALTER TABLE notifications
  ALTER COLUMN reason TYPE VARCHAR(40),
  ALTER COLUMN reason SET DEFAULT 'incident_created',
  ALTER COLUMN risk_score TYPE DOUBLE PRECISION USING risk_score::DOUBLE PRECISION,
  ALTER COLUMN risk_score SET DEFAULT 50;
