-- Direito de eliminação (LGPD art. 18, VI) e revogação de sessão.
--
-- 1. incidents.reported_by usava ON DELETE RESTRICT: quem já registrou uma ocorrência
--    nunca podia ser removido do banco. A ocorrência é valor público e permanece; o
--    vínculo com o denunciante é que precisa poder ser desfeito.
-- 2. revoked_tokens dá ao logout efeito real no servidor: hoje o token continua válido
--    até expirar, mesmo depois de o aparelho apagar a credencial.

ALTER TABLE incidents
  DROP CONSTRAINT IF EXISTS incidents_reported_by_fkey;

ALTER TABLE incidents
  ADD CONSTRAINT incidents_reported_by_fkey
  FOREIGN KEY (reported_by) REFERENCES users(id) ON DELETE SET NULL;

-- Marca contas anonimizadas: bloqueia login e exclui a conta dos alertas de proximidade.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS users_active_accounts_idx
  ON users (id) WHERE deleted_at IS NULL;

-- incident_reviews.reviewer_id também impedia a remoção do registro do usuário.
ALTER TABLE incident_reviews
  DROP CONSTRAINT IF EXISTS incident_reviews_reviewer_id_fkey;

ALTER TABLE incident_reviews
  ADD CONSTRAINT incident_reviews_reviewer_id_fkey
  FOREIGN KEY (reviewer_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE citizen_contributions
  DROP CONSTRAINT IF EXISTS citizen_contributions_user_id_fkey;

ALTER TABLE citizen_contributions
  ADD CONSTRAINT citizen_contributions_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

CREATE TABLE IF NOT EXISTS revoked_tokens (
  jti UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- A tabela só precisa guardar tokens que ainda não expiraram; o índice sustenta a limpeza.
CREATE INDEX IF NOT EXISTS revoked_tokens_expires_at_idx
  ON revoked_tokens (expires_at);
