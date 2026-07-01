from pydantic import BaseModel, Field
from typing import List, Optional
from enum import Enum
from app.models.email import Email

class SubscriptionStatus(str, Enum):
    UNKNOWN = "unknown"
    DETECTED = "detected"
    CONFIRMED = "confirmed"
    ACTIVE = "active"
    CANCELLED = "cancelled"

class Money(BaseModel):
    amount: float
    currency: str = "CNY"

class Subscription(BaseModel):
    id: Optional[str] = None
    merchant: str
    price: Money
    status: SubscriptionStatus = SubscriptionStatus.DETECTED
    confidence: float = Field(..., ge=0.0, le=1.0)
    last_seen_email_id: Optional[str] = None
    history: List[Email] = []
    evidence: List[str] = []
    first_seen: Optional[str] = None
    last_seen: Optional[str] = None
    cycle_detected: str = "monthly"
    stability_score: float = 0.0
    state: str = "active"
    user_trust_score: float = 1.0
    decision_history: List[str] = []

class SubscriptionListResponse(BaseModel):
    subscriptions: List[Subscription]
    monthly_cost: float
    yearly_cost: float
    subscription_count: int

