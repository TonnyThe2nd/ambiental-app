"""Compatibility facade; contracts now live in their bounded contexts."""
from .alerts.presentation.schemas import NotificationOutput
from .identity.presentation.schemas import (AlertPreferencesInput, AuthResponse, LoginInput,
    RegisterInput, Severity, UserLocationInput, UserOutput)
from .incidents.presentation.schemas import (CommunityValidationInput, IncidentAccepted,
    IncidentInput, IncidentOutput, ReviewInput)
from .monitoring.presentation.schemas import EnvironmentalObservationInput

__all__ = ["AlertPreferencesInput", "AuthResponse", "CommunityValidationInput",
    "EnvironmentalObservationInput", "IncidentAccepted", "IncidentInput", "IncidentOutput",
    "LoginInput", "NotificationOutput", "RegisterInput", "ReviewInput", "Severity",
    "UserLocationInput", "UserOutput"]
