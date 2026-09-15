-- Horários silenciosos devem ser avaliados no fuso configurado de cada usuário,
-- não no fuso da infraestrutura onde o PostgreSQL está executando.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS timezone TEXT;

UPDATE users
SET timezone = 'America/Sao_Paulo'
WHERE timezone IS NULL OR timezone = '';

ALTER TABLE users
  ALTER COLUMN timezone SET DEFAULT 'America/Sao_Paulo',
  ALTER COLUMN timezone SET NOT NULL;
