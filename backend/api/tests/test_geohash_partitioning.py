import pytest

from src.shared.domain import geohash


def test_codifica_valores_de_referencia():
    assert geohash.encode(57.64911, 10.40744, 11) == "u4pruydqqvj"
    assert geohash.encode(-23.5505, -46.6333) == "6gyf4bf"  # São Paulo, precisão 7


def test_celula_contem_o_ponto_codificado():
    lat_min, lon_min, lat_max, lon_max = geohash.bounds(geohash.encode(-23.5505, -46.6333, 6))
    assert lat_min <= -23.5505 <= lat_max and lon_min <= -46.6333 <= lon_max


def test_vizinhas_incluem_a_propria_celula_e_mantem_precisao():
    cells = geohash.neighbors("6gyf")
    assert len(cells) == 9 and "6gyf" in cells
    assert all(len(cell) == 4 for cell in cells)


def test_particao_e_assinatura_por_prefixo():
    assert geohash.partition_of("6gyf4bf") == "6gyf"
    assert geohash.matches("6gyf4bf", {"6gy"})
    assert not geohash.matches("6gyc000", {"6gyf"})
    assert not geohash.matches(None, {"6gyf"})


@pytest.mark.parametrize("latitude,longitude,precision", [(91, 0, 5), (0, 181, 5), (0, 0, 13)])
def test_rejeita_entrada_invalida(latitude, longitude, precision):
    with pytest.raises(ValueError):
        geohash.encode(latitude, longitude, precision)


def test_valida_alfabeto_base32():
    assert geohash.is_valid("6gyf")
    assert not geohash.is_valid("6gya")  # "a" não pertence ao alfabeto
    assert not geohash.is_valid("")
