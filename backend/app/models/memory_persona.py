from pydantic import BaseModel
from typing import List, Dict, Any

class FactualMemory(BaseModel):
    user_id: str
    facts: List[str] = []

class BehaviorMemory(BaseModel):
    patterns: List[str] = []

class EmotionalTimelineEntry(BaseModel):
    date: str
    emotion: str

class MemorySystem(BaseModel):
    factual: FactualMemory
    behavior: BehaviorMemory
    timeline: List[EmotionalTimelineEntry] = []

class DynamicPersona(BaseModel):
    tone: str # gentle | structured | energetic
    style: str # short-response | reflective | coaching
    behavior_rules: List[str] = []
