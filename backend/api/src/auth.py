import os
from datetime import datetime, timedelta, timezone
from typing import Annotated
from uuid import UUID, uuid4

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt.exceptions import InvalidTokenError
from pwdlib import PasswordHash
from psycopg.errors import UniqueViolation

from .database import pool
from .models import AuthResponse, LoginInput, RegisterInput, UserLocationInput, UserOutput

JWT_SECRET = os.getenv("JWT_SECRET")
if not JWT_SECRET or len(JWT_SECRET) < 32:
    raise RuntimeError("JWT_SECRET precisa ter pelo menos 32 caracteres.")

JWT_ALGORITHM = "HS256"
JWT_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", "60"))
password_hash = PasswordHash.recommended()
dummy_hash = password_hash.hash("urbaneye-dummy-password")
bearer = HTTPBearer(auto_error=False)


def create_access_token(user_id: UUID) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {"sub": str(user_id), "iat": now, "exp": now + timedelta(minutes=JWT_EXPIRE_MINUTES)},
        JWT_SECRET,
        algorithm=JWT_ALGORITHM,
    )


async def register_user(data: RegisterInput) -> AuthResponse:
    user_id = uuid4()
    email = data.email.strip().lower()
    hashed = password_hash.hash(data.password)
    try:
        async with pool.connection() as connection:
            await connection.execute(
                """
                INSERT INTO users (id, name, email, password_hash, latitude, longitude, location, location_updated_at)
                VALUES (%s, %s, %s, %s, %s, %s,
                        ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, NOW())
                """,
                (user_id, data.name.strip(), email, hashed, data.latitude, data.longitude,
                 data.longitude, data.latitude),
            )
            await connection.commit()
    except UniqueViolation as error:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="E-mail já cadastrado.") from error
    user = UserOutput(id=user_id, name=data.name.strip(), email=email)
    return AuthResponse(access_token=create_access_token(user_id), user=user)


async def update_user_location(user_id: UUID, data: UserLocationInput) -> None:
    async with pool.connection() as connection:
        await connection.execute(
            """
            UPDATE users
            SET latitude = %s, longitude = %s,
                location = ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography,
                fcm_token = COALESCE(%s, fcm_token), location_updated_at = NOW()
            WHERE id = %s
            """,
            (data.latitude, data.longitude, data.longitude, data.latitude, data.fcm_token, user_id),
        )
        await connection.commit()


async def login_user(data: LoginInput) -> AuthResponse:
    async with pool.connection() as connection:
        result = await connection.execute(
            "SELECT id, name, email, password_hash FROM users WHERE email = %s",
            (data.email.strip().lower(),),
        )
        row = await result.fetchone()
    valid = password_hash.verify(data.password, row["password_hash"] if row else dummy_hash)
    if row is None or not valid:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="E-mail ou senha inválidos.")
    user = UserOutput(id=row["id"], name=row["name"], email=row["email"])
    return AuthResponse(access_token=create_access_token(row["id"]), user=user)


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> UserOutput:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Autenticação necessária.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise unauthorized
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = UUID(payload["sub"])
    except (InvalidTokenError, KeyError, ValueError) as error:
        raise unauthorized from error
    async with pool.connection() as connection:
        result = await connection.execute("SELECT id, name, email FROM users WHERE id = %s", (user_id,))
        row = await result.fetchone()
    if row is None:
        raise unauthorized
    return UserOutput(id=row["id"], name=row["name"], email=row["email"])


CurrentUser = Annotated[UserOutput, Depends(get_current_user)]
