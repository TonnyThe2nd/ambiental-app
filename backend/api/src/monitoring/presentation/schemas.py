from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field

class EnvironmentalObservationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    region_key: str = Field(validation_alias="regionKey", min_length=2, max_length=80)
    observed_at: datetime = Field(validation_alias="observedAt")
    source: str = Field(min_length=2, max_length=100)
    temperature_c: float | None = Field(default=None, validation_alias="temperatureC", ge=-80, le=70)
    humidity_percent: float | None = Field(default=None, validation_alias="humidityPercent", ge=0, le=100)
    rainfall_mm: float | None = Field(default=None, validation_alias="rainfallMm", ge=0)
    air_quality_index: int | None = Field(default=None, validation_alias="airQualityIndex", ge=0, le=500)
    payload: dict = Field(default_factory=dict)
