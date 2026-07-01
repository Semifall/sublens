import uuid
from typing import Dict, Any, List, Optional
from pydantic import BaseModel, Field
from datetime import datetime

class CoreEvent(BaseModel):
    event_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    session_id: str
    event_type: str
    timestamp: int = Field(default_factory=lambda: int(datetime.utcnow().timestamp()))
    payload: Dict[str, Any] = {}
    context: Dict[str, Any] = {}

class SessionStore(BaseModel):
    session_id: str
    user_id: str
    start_time: int
    end_time: Optional[int] = None
    event_count: int = 0
    exit_reason: Optional[str] = None
    completion_flag: bool = False

class ErrorIntelligenceCore(BaseModel):
    error_code: str
    error_type: str
    input_pattern: str
    frequency: int = 0
    avg_session_drop_rate: float = 0.0
    example_cases: List[str] = []
    fix_strategy: str
