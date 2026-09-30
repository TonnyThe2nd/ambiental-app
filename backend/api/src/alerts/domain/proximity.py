from dataclasses import dataclass
from uuid import UUID


@dataclass(frozen=True)
class NearbyIncident:
    id: UUID
    category: str
    severity: str
    distance_km: float
    latitude: float | None = None
    longitude: float | None = None
    impact_radius_m: int | None = None


@dataclass(frozen=True)
class ProximityAlert:
    id: UUID
    user_id: UUID
    incident: NearbyIncident
    title: str
    message: str
