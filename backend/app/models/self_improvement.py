from typing import Dict, Any, List, Optional
from pydantic import BaseModel, Field

class ProblemCluster(BaseModel):
    problem_cluster: str
    impact_score: float
    root_pattern: List[str]
    fix_target: str

class FixProposal(BaseModel):
    fix_id: str
    target: str
    change: List[str]
    expected_effect: str

class MetricsJudgeResult(BaseModel):
    winner: str
    delta: Dict[str, str]
    group_a_metrics: Dict[str, Any]
    group_b_metrics: Dict[str, Any]
