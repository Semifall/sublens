from pydantic import BaseModel
from typing import Dict, Any

class UserStateEvaluation(BaseModel):
    user_id: str
    current_state: str # cold_start | exploration | habit | at_risk
    metrics: Dict[str, Any]
    active_prompt_template: str
