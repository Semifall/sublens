from pydantic import BaseModel

class Email(BaseModel):
    id: str
    user_id: str
    gmail_id: str
    thread_id: str
    sender: str
    subject: str
    snippet: str
    received_at: str
    created_at: str

class Recognition(BaseModel):
    id: str
    email_id: str
    merchant: str
    price: float
    currency: str = "USD"
    renewal: str # monthly | yearly | one-time | unknown
    confidence: float
    source: str # rule | fingerprint | ai
    created_at: str

class Subscription(BaseModel):
    id: str
    user_id: str
    merchant: str
    status: str # unknown | detected | confirmed | active | canceled
    price: float
    renewal: str # monthly | yearly | one-time | unknown
    next_billing: str # YYYY-MM-DD
    confidence: float
    created_at: str

class GmailAccount(BaseModel):
    id: str
    email: str
    oauth_provider: str = "google"
    created_at: str

class UserGmailLink(BaseModel):
    user_id: str
    gmail_account_id: str
