from pathlib import Path

MIGRATION = Path(__file__).parents[2] / "database" / "migrations" / "013_geohash_partitioning_and_photos.sql"


def test_migracao_e_idempotente_e_cria_indice_de_prefixo():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "ADD COLUMN IF NOT EXISTS geohash" in sql
    assert "WHERE geohash IS NULL" in sql  # backfill só do que falta, seguro para reaplicar
    assert "text_pattern_ops" in sql      # LIKE 'prefixo%' usa o índice
    assert "CREATE TABLE IF NOT EXISTS incident_photos" in sql
    assert "5242880" in sql               # mesmo limite de 5 MB da API
