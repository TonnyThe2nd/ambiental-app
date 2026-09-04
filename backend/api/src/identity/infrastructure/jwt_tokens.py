import os
from datetime import datetime, timedelta, timezone
from uuid import UUID

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
            {"sub": str(user_id), "iat": now, "exp": now + timedelta(minutes=self._minutes)},
            self._secret, algorithm="HS256",
        )

    def subject(self, token: str) -> UUID:
        return UUID(jwt.decode(token, self._secret, algorithms=["HS256"])["sub"])
