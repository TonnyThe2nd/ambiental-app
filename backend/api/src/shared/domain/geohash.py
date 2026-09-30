"""GeoHash: particionamento geográfico usado para shards de tempo real, cache e mapa de calor.

Implementação pura (sem dependências) para que o domínio continue testável sem PostGIS.
A mesma codificação é produzida no banco por ``ST_GeoHash`` e no app Flutter.

Tamanho aproximado das células no equador:
    precisão 4 ≈ 39 km x 19,5 km   (partição de tempo real/assinaturas)
    precisão 5 ≈ 4,9 km x 4,9 km   (mapa de calor)
    precisão 6 ≈ 1,2 km x 0,6 km
    precisão 7 ≈ 153 m x 153 m     (armazenado em cada ocorrência)
"""

_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"
_DECODE = {char: index for index, char in enumerate(_BASE32)}

STORAGE_PRECISION = 7
PARTITION_PRECISION = 4
HEATMAP_PRECISIONS = range(3, 8)


def encode(latitude: float, longitude: float, precision: int = STORAGE_PRECISION) -> str:
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        raise ValueError("Coordenadas fora do intervalo válido.")
    if not 1 <= precision <= 12:
        raise ValueError("A precisão do GeoHash deve estar entre 1 e 12.")
    lat_range, lon_range = [-90.0, 90.0], [-180.0, 180.0]
    chars, bits, bit_count, even = [], 0, 0, True
    while len(chars) < precision:
        target, value = (lon_range, longitude) if even else (lat_range, latitude)
        middle = (target[0] + target[1]) / 2
        if value >= middle:
            bits = (bits << 1) | 1
            target[0] = middle
        else:
            bits <<= 1
            target[1] = middle
        even = not even
        bit_count += 1
        if bit_count == 5:
            chars.append(_BASE32[bits])
            bits, bit_count = 0, 0
    return "".join(chars)


def bounds(geohash: str) -> tuple[float, float, float, float]:
    """Retorna (lat_min, lon_min, lat_max, lon_max) da célula."""
    if not is_valid(geohash):
        raise ValueError("GeoHash inválido.")
    lat_range, lon_range, even = [-90.0, 90.0], [-180.0, 180.0], True
    for char in geohash:
        value = _DECODE[char]
        for shift in range(4, -1, -1):
            target = lon_range if even else lat_range
            middle = (target[0] + target[1]) / 2
            if (value >> shift) & 1:
                target[0] = middle
            else:
                target[1] = middle
            even = not even
    return lat_range[0], lon_range[0], lat_range[1], lon_range[1]


def decode(geohash: str) -> tuple[float, float]:
    """Centro da célula (latitude, longitude)."""
    lat_min, lon_min, lat_max, lon_max = bounds(geohash)
    return (lat_min + lat_max) / 2, (lon_min + lon_max) / 2


def is_valid(geohash: str) -> bool:
    return bool(geohash) and len(geohash) <= 12 and all(char in _DECODE for char in geohash)


def neighbors(geohash: str) -> list[str]:
    """A própria célula e as 8 vizinhas, na mesma precisão."""
    lat_min, lon_min, lat_max, lon_max = bounds(geohash)
    lat_step, lon_step = lat_max - lat_min, lon_max - lon_min
    center_lat, center_lon = (lat_min + lat_max) / 2, (lon_min + lon_max) / 2
    cells: list[str] = []
    for d_lat in (-1, 0, 1):
        for d_lon in (-1, 0, 1):
            lat = center_lat + d_lat * lat_step
            lon = ((center_lon + d_lon * lon_step + 180) % 360) - 180
            if -90 <= lat <= 90:
                cell = encode(lat, lon, len(geohash))
                if cell not in cells:
                    cells.append(cell)
    return cells


def partition_of(geohash: str) -> str:
    """Prefixo que define a partição (shard) geográfica de um evento."""
    return geohash[:PARTITION_PRECISION]


def matches(event_geohash: str | None, subscriptions: set[str]) -> bool:
    """Um evento interessa a quem assinou qualquer prefixo da sua célula."""
    if not event_geohash:
        return False
    return any(event_geohash.startswith(prefix) for prefix in subscriptions)
