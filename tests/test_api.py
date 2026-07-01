import pytest
import sys
import os
from fastapi.testclient import TestClient

# Adjust path to import backend app
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend")))

from app.main import app

client = TestClient(app)

def test_root_endpoint():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["app"] == "Sublens Backend API"
    assert response.json()["status"] == "healthy"

def test_login_endpoint():
    response = client.post("/api/v1/login", json={"access_token": "valid_mock_token"})
    assert response.status_code == 200
    assert response.json()["status"] == "success"
    assert response.json()["email"] == "user@example.com"
    
    # Test invalid token
    response_invalid = client.post("/api/v1/login", json={"access_token": "invalid_token"})
    assert response_invalid.status_code == 401

def test_get_emails():
    # Calling without authorization header will trigger mock fallback
    response = client.get("/api/v1/emails?limit=5")
    assert response.status_code == 200
    data = response.json()
    assert "emails" in data
    assert len(data["emails"]) > 0
    # Check email object schema
    email = data["emails"][0]
    assert "id" in email
    assert "subject" in email
    assert "sender" in email

def test_scan_flow():
    # 1. Trigger scan
    response_start = client.post("/api/v1/scan", json={"access_token": "mock_token"})
    assert response_start.status_code == 200
    job_id = response_start.json()["job_id"]
    assert job_id is not None
    assert response_start.json()["status"] == "pending"

    # 2. Poll status (with simple sleep to wait for mock scan execution if running in background)
    # Since mock scan completes very quickly, we can poll
    import time
    
    max_retries = 5
    completed = False
    
    for _ in range(max_retries):
        response_status = client.get(f"/api/v1/scan/{job_id}")
        assert response_status.status_code == 200
        status_data = response_status.json()
        
        if status_data["status"] == "completed":
            completed = True
            assert "subscriptions" in status_data
            assert "summary" in status_data
            
            summary = status_data["summary"]
            assert summary["subscription_count"] > 0
            assert summary["monthly_cost"] > 0
            assert summary["yearly_cost"] > 0
            
            # Check subscriptions structure
            subscriptions = status_data["subscriptions"]
            merchants = [s["merchant"] for s in subscriptions]
            assert "Netflix" in merchants
            assert "Spotify" in merchants
            break
            
        time.sleep(0.5)
        
    assert completed, "Scan job did not complete within timeout"

def test_decision_events():
    event_data = {
        "subscription_id": "test-sub-123",
        "user_action": "accept",
        "ai_recommendation": "cancel",
        "confidence": 0.85,
        "impact_value": 290.0
    }
    
    # 1. Create decision event
    response_post = client.post("/api/v1/decision-events", json=event_data)
    assert response_post.status_code == 200
    res_json = response_post.json()
    assert res_json["subscription_id"] == "test-sub-123"
    assert res_json["user_action"] == "accept"
    assert res_json["ai_recommendation"] == "cancel"
    assert res_json["confidence"] == 0.85
    assert res_json["impact_value"] == 290.0
    assert "id" in res_json
    assert "timestamp" in res_json
    
    event_id = res_json["id"]
    
    # 2. Get list of decision events
    response_get = client.get("/api/v1/decision-events")
    assert response_get.status_code == 200
    events = response_get.json()
    assert len(events) > 0
    
    matched = [e for e in events if e["id"] == event_id]
    assert len(matched) == 1
    assert matched[0]["subscription_id"] == "test-sub-123"

def test_core_events_tracking():
    # 1. Create Core Event
    event_payload = {
        "user_id": "u123",
        "session_id": "s456",
        "event_type": "input_submit",
        "payload": {
            "input_text": "I am feeling anxious",
            "emotion_tag": "anxiety"
        },
        "context": {
            "step_stage": "step2_error_intelligence",
            "user_state": "active"
        }
    }
    
    response_post = client.post("/api/v1/events", json=event_payload)
    assert response_post.status_code == 200
    res_json = response_post.json()
    assert res_json["user_id"] == "u123"
    assert res_json["session_id"] == "s456"
    assert res_json["event_type"] == "input_submit"
    assert "event_id" in res_json
    assert "timestamp" in res_json
    
    # 2. Get Analytics Session details
    response_session = client.get("/api/v1/analytics/session/s456")
    assert response_session.status_code == 200
    session_data = response_session.json()
    assert "session" in session_data
    assert "events" in session_data
    assert session_data["session"]["session_id"] == "s456"
    assert session_data["session"]["event_count"] == 1
    assert len(session_data["events"]) == 1
    
    # 3. Retrieve Error Intelligence Core details
    response_error = client.get("/api/v1/analytics/error/E102")
    assert response_error.status_code == 200
    error_data = response_error.json()
    assert error_data["error_code"] == "E102"
    assert error_data["error_type"] == "semantic_mismatch"
    assert error_data["fix_strategy"] == "add_empathy_layer_v2"

