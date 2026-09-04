class DomainError(Exception):
    """Base exception for expected business-rule violations."""


class EntityNotFound(DomainError):
    pass


class ConflictError(DomainError):
    pass


class ForbiddenOperation(DomainError):
    pass
