import os
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

import jwt


class JwtTokenService:
    def __init__(self):
        self._secret = os.getenv("JWT_SECRET")
        if not self._secret or len(self._secret) < 32:
            raise RuntimeError("JWT_SECRET precisa ter pelo menos 32 caracteres.")
        self._minutes = int(os.getenv("JWT_EXPIRE_MINUTES", "60"))

    def create(self, user_id: UUID) -> str:
        now = datetime.now(timezone.utc)
        return jwt.encode(
            {"sub": str(user_id), "jti": str(uuid4()), "iat": now,
             "exp": now + timedelta(minutes=self._minutes)},
            self._secret, algorithm="HS256",
        )

    def claims(self, token: str) -> dict:
        return jwt.decode(token, self._secret, algorithms=["HS256"])

    def subject(self, token: str) -> UUID:
        return UUID(self.claims(token)["sub"])

    def identity(self, token: str) -> tuple[UUID, UUID | None, datetime]:
        payload = self.claims(token)
        raw_jti = payload.get("jti")
        expires_at = datetime.fromtimestamp(payload["exp"], tz=timezone.utc)
        return UUID(payload["sub"]), UUID(raw_jti) if raw_jti else None, expires_at
