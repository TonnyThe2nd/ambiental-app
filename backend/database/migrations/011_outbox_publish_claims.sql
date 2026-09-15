-- A publicação no broker ocorre fora da transação do banco. Estes campos funcionam
-- como uma reserva com prazo: outro poller pode recuperar uma reserva abandonada,
-- mas não pode confirmar ou reagendar o trabalho de quem ainda a possui.
ALTER TABLE outbox
  ADD COLUMN IF NOT EXISTS processing_token UUID,
  ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS outbox_claimable_idx
  ON outbox (available_at, locked_until, created_at)
  WHERE processing_token IS NULL;
