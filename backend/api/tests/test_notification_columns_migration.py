from pathlib import Path


def test_migracao_corrige_colunas_ja_existentes_de_notifications():
    migration = (
        Path(__file__).parents[2]
        / "database"
        / "migrations"
        / "010_fix_notification_columns.sql"
    ).read_text(encoding="utf-8")

    assert "ALTER COLUMN reason TYPE VARCHAR(40)" in migration
    assert "ALTER COLUMN reason SET DEFAULT 'incident_created'" in migration
    assert "ALTER COLUMN risk_score TYPE DOUBLE PRECISION" in migration
    assert "ALTER COLUMN risk_score SET DEFAULT 50" in migration
    assert not any(
        line.strip().startswith("ADD COLUMN IF NOT EXISTS")
        for line in migration.splitlines()
    )
