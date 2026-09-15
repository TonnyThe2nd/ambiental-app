"""Compatibility facade; contracts now live in their bounded contexts."""
from .alerts.presentation.schemas import NotificationOutput
from .identity.presentation.schemas import (AlertPreferencesInput, AuthResponse, LoginInput,
    RegisterInput, Severity, UserLocationInput, UserOutput)
from .incidents.presentation.schemas import (CampaignInput, CommunityValidationInput, IncidentAccepted,
    IncidentInput, IncidentOutput, ReporterPublic, ReviewInput, SensitiveAreaInput)
from .monitoring.presentation.schemas import EnvironmentalObservationInput

__all__ = ["AlertPreferencesInput", "AuthResponse", "CampaignInput", "CommunityValidationInput",
    "EnvironmentalObservationInput", "IncidentAccepted", "IncidentInput", "IncidentOutput",
    "LoginInput", "NotificationOutput", "RegisterInput", "ReporterPublic", "ReviewInput", "SensitiveAreaInput", "Severity",
    "UserLocationInput", "UserOutput"]
