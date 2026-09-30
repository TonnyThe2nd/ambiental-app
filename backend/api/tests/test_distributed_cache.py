import asyncio

from src.shared.infrastructure.cache import VERSION_KEY, DistributedCache


class FakeRedis:
    def __init__(self, broken=False):
        self.data, self.broken = {}, broken

    async def get(self, key):
        if self.broken:
            raise ConnectionError("redis fora do ar")
        return self.data.get(key)

    async def set(self, key, value, ex=None):
        self.data[key] = value

    async def incr(self, key):
        self.data[key] = int(self.data.get(key, 0)) + 1


def _cache(fake):
    cache = DistributedCache(url="redis://fake")
    cache._client = fake
    return cache


def test_sem_redis_configurado_le_direto_do_banco():
    calls = []
    async def loader():
        calls.append(1)
        return [1]
    cache = DistributedCache(url="")
    assert asyncio.run(cache.get_or_load("x", {}, loader)) == [1]
    assert asyncio.run(cache.get_or_load("x", {}, loader)) == [1]
    assert len(calls) == 2


def test_segunda_leitura_vem_do_cache_e_invalidacao_troca_a_versao():
    calls = []
    async def loader():
        calls.append(1)
        return {"total": len(calls)}
    cache = _cache(FakeRedis())
    async def scenario():
        first = await cache.get_or_load("heatmap", {"p": 5}, loader)
        second = await cache.get_or_load("heatmap", {"p": 5}, loader)
        await cache.invalidate()
        third = await cache.get_or_load("heatmap", {"p": 5}, loader)
        return first, second, third
    first, second, third = asyncio.run(scenario())
    assert first == second == {"total": 1}
    assert third == {"total": 2}
    assert cache._client.data[VERSION_KEY] == 1


def test_falha_do_redis_nao_derruba_a_leitura():
    async def loader():
        return ["banco"]
    assert asyncio.run(_cache(FakeRedis(broken=True)).get_or_load("x", {}, loader)) == ["banco"]
