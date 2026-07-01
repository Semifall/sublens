from pydantic import BaseModel
from typing import Dict, Any, List

class ProactiveTrigger(BaseModel):
    trigger_type: str # emotion_intervention | insight_push | memory_reflection | behavior_nudge | no_action
    priority: str # high | medium | low
    reason: str
    trigger_score: float
    recommended_action: str

class AutonomousSchedulerStatus(BaseModel):
    last_trigger_time: int = 0
    cooldown_active: bool = False
    active_triggers: List[ProactiveTrigger] = []
