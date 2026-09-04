"""Compatibility facade for shared database infrastructure."""
from .shared.infrastructure.database import database, pool

lifespan_pool = database.lifespan
__all__ = ["database", "lifespan_pool", "pool"]
