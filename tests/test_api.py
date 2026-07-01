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
