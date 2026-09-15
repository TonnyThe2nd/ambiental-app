from pathlib import Path


def test_migration_activates_civic_tables_and_trust_adjustments():
    migration = Path(__file__).parents[2] / "database" / "migrations" / "012_activate_civic_features.sql"
    sql = migration.read_text(encoding="utf-8")
    assert "citizen_contributions_unique_incident_type_idx" in sql
    assert "campaigns_active_schedule_idx" in sql
    assert "incident_trust_adjustments" in sql
