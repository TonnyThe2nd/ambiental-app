import logging
import os
from pathlib import Path

import psycopg

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("urbaneye.migrate")


def run() -> None:
    database_url = os.environ["DATABASE_URL"]
    migrations_dir = Path(os.getenv("MIGRATIONS_DIR", "/app/migrations"))
    files = sorted(migrations_dir.glob("*.sql"))
    if not files:
        raise RuntimeError(f"Nenhuma migração encontrada em {migrations_dir}")
    with psycopg.connect(database_url) as connection:
        for path in files:
            logger.info("Aplicando %s", path.name)
            with connection.transaction():
                connection.execute(path.read_text(encoding="utf-8"))
    logger.info("Migrações concluídas: %s", len(files))


if __name__ == "__main__":
    run()
