from uuid import uuid4

from src.identity.domain.entities import User, UserRole


def test_moderator_can_moderate():
    user = User(uuid4(), "Moderadora", "mod@example.com", UserRole.MODERATOR)
    assert user.can_moderate
    assert not user.is_administrator


def test_citizen_cannot_moderate():
    user = User(uuid4(), "Cidadão", "citizen@example.com")
    assert not user.can_moderate
