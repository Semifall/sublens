from pydantic import BaseModel
from typing import List, Optional

class Email(BaseModel):
    id: str
    subject: str
    sender: str
    snippet: str
    date: str

class EmailListResponse(BaseModel):
    emails: List[Email]
    next_cursor: Optional[str] = None
