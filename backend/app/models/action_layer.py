from pydantic import BaseModel
from typing import List, Dict, Any

class ActionItem(BaseModel):
    tool: str
    params: Dict[str, Any] = {}

class ActionPlan(BaseModel):
    intent: str
    actions: List[ActionItem] = []

class ActionExecutionResult(BaseModel):
    plan: ActionPlan
    execution_logs: List[str] = []
    final_output: Dict[str, Any] = {}
