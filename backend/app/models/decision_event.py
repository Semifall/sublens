import uuid
from typing import Literal, Optional
from pydantic import BaseModel, Field
from datetime import datetime

class DecisionEvent(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    subscription_id: str
    user_action: Literal["accept", "ignore", "cancel", "ask"]
    ai_recommendation: Literal["cancel", "keep", "downgrade"]
    confidence: float = Field(..., ge=0.0, le=1.0)
    impact_value: float = 0.0
    timestamp: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
