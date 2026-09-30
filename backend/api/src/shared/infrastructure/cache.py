"""Cache distribuído em Redis para leituras de alta vazão (mapa e mapa de calor).

Consistência eventual: cada chave embute a "versão" atual do conjunto de ocorrências.
Quando um evento de ocorrência chega pelo barramento, a versão é incrementada e as
chaves antigas deixam de ser lidas (e expiram pelo TTL). Assim nenhuma instância precisa
apagar chaves de outra, e o PostgreSQL continua sendo a fonte autoritativa.

O cache é opcional: sem ``REDIS_URL`` (ou com o Redis fora do ar) as leituras vão direto
ao banco. Uma falha do cache nunca derruba a requisição.
"""
import hashlib
import json
import logging
import os
from typing import Any, Awaitable, Callable

logger = logging.getLogger("urbaneye.cache")
VERSION_KEY = "urbaneye:incidents:version"


class DistributedCache:
    def __init__(self, url: str | None = None, default_ttl: int | None = None) -> None:
        self._url = url if url is not None else os.getenv("REDIS_URL", "")
        self._ttl = default_ttl or int(os.getenv("CACHE_TTL_SECONDS", "30"))
        self._client = None

    @property
    def enabled(self) -> bool:
        return bool(self._url)

    def _redis(self):
        if self._client is None and self.enabled:
            import redis.asyncio as redis  # dependência opcional em testes
            self._client = redis.from_url(self._url, decode_responses=True,
                                          socket_timeout=0.5, socket_connect_timeout=0.5)
        return self._client

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    async def _version(self) -> str:
        return str(await self._redis().get(VERSION_KEY) or 0)

    @staticmethod
    def key(namespace: str, params: dict, version: str) -> str:
        digest = hashlib.sha256(json.dumps(params, sort_keys=True, default=str).encode()).hexdigest()[:24]
        return f"urbaneye:{namespace}:v{version}:{digest}"

    async def get_or_load(self, namespace: str, params: dict,
                          loader: Callable[[], Awaitable[Any]], ttl: int | None = None) -> Any:
        if not self.enabled:
            return await loader()
        try:
            key = self.key(namespace, params, await self._version())
            cached = await self._redis().get(key)
            if cached is not None:
                return json.loads(cached)
        except Exception as error:  # Redis indisponível: segue sem cache
            logger.warning("Cache indisponível (%s); lendo do banco", error)
            return await loader()
        value = await loader()
        try:
            await self._redis().set(key, json.dumps(value, default=str), ex=ttl or self._ttl)
        except Exception as error:
            logger.warning("Falha ao gravar no cache: %s", error)
        return value

    async def invalidate(self) -> None:
        """Avança a versão; leituras seguintes ignoram as chaves anteriores."""
        if not self.enabled:
            return
        try:
            await self._redis().incr(VERSION_KEY)
        except Exception as error:
            logger.warning("Falha ao invalidar o cache: %s", error)


cache = DistributedCache()
