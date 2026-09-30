import asyncio
from uuid import uuid4

import pytest

from src.incidents.application.ports import HeatmapFilters
from src.incidents.application.use_cases import IncidentPhotos, ListHeatmap, detect_image_type


class FakeRepository:
    def __init__(self):
        self.photos = {}

    async def heatmap(self, filters):
        return [{"cell": "6gyf4", "total": 3, "avg_risk": 60.0, "max_risk": 80.0, "critical": 1,
                 "categories": ["alagamento"]}]

    async def save_photo(self, incident_id, user_id, content, content_type):
        self.photos[incident_id] = (content, content_type)

    async def load_photo(self, incident_id):
        return None


def _filters(**overrides):
    values = {"precision": 5, "days": 30, "categories": [], "active_only": True, "cells": []}
    return HeatmapFilters(**{**values, **overrides})


def test_mapa_de_calor_devolve_centro_e_limites_da_celula():
    cells = asyncio.run(ListHeatmap(FakeRepository()).execute(_filters()))
    lat_min, lon_min, lat_max, lon_max = cells[0]["bounds"]
    assert lat_min < cells[0]["latitude"] < lat_max and lon_min < cells[0]["longitude"] < lon_max
    assert cells[0]["total"] == 3


@pytest.mark.parametrize("overrides", [{"precision": 9}, {"cells": ["6gya"]}, {"cells": ["6gyf4bf"]},
                                       {"cells": ["6gyf"] * 51}])
def test_filtros_do_mapa_de_calor_invalidos(overrides):
    with pytest.raises(ValueError):
        _filters(**overrides)


def test_tipo_da_foto_vem_dos_bytes():
    assert detect_image_type(b"\xff\xd8\xff\xe0resto") == "image/jpeg"
    assert detect_image_type(b"\x89PNG\r\n\x1a\nresto") == "image/png"
    assert detect_image_type(b"RIFF0000WEBPVP8 ") == "image/webp"
    with pytest.raises(ValueError):
        detect_image_type(b"<html>")


def test_foto_grande_ou_vazia_e_recusada():
    photos = IncidentPhotos(FakeRepository())
    with pytest.raises(OverflowError):
        asyncio.run(photos.save(uuid4(), uuid4(), b"\xff\xd8\xff" + b"0" * photos.max_bytes))
    with pytest.raises(ValueError):
        asyncio.run(photos.save(uuid4(), uuid4(), b""))


def test_foto_valida_e_gravada_com_tipo_detectado():
    repository, incident_id = FakeRepository(), uuid4()
    asyncio.run(IncidentPhotos(repository).save(incident_id, uuid4(), b"\xff\xd8\xffdados"))
    assert repository.photos[incident_id][1] == "image/jpeg"
