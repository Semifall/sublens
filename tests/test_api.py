import pytest
import sys
import os
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend")))

from app.main import app

client = TestClient(app)

def test_root_endpoint():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["app"] == "Sublens Backend API"
    assert response.json()["status"] == "healthy"

def test_auth_google_flow():
    # Test valid exchange
    payload = {
        "google_oauth_token": "valid_google_token",
        "email": "alex@gmail.com",
        "name": "Alex"
    }
    response = client.post("/api/v1/auth/google", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert "jwt_token" in data
    assert "refresh_token" in data
    assert data["email"] == "alex@gmail.com"
    assert data["name"] == "Alex"
    
    # Test invalid OAuth token
    payload_invalid = {
        "google_oauth_token": "invalid_token",
        "email": "alex@gmail.com",
        "name": "Alex"
    }
    response_invalid = client.post("/api/v1/auth/google", json=payload_invalid)
    assert response_invalid.status_code == 400

def test_scan_jobs_flow():
    # 1. Trigger scan
    response_start = client.post("/api/v1/scan")
    assert response_start.status_code == 200
    job_id = response_start.json()["job_id"]
    assert job_id is not None
    assert response_start.json()["status"] == "pending"
    
    # 2. Check status (mock simulation updates to done instantly or quickly)
    import time
    max_retries = 10
    done = False
    for _ in range(max_retries):
        response_status = client.get(f"/api/v1/scan/{job_id}")
        assert response_status.status_code == 200
        status_data = response_status.json()
        if status_data["status"] == "done":
            done = True
            assert status_data["progress"] == 100
            assert status_data["emails_scanned"] > 0
            assert status_data["subscriptions_found"] > 0
            break
        time.sleep(0.1)
    assert done

def test_scan_history():
    response = client.get("/api/v1/scan/history")
    assert response.status_code == 200
    data = response.json()
    assert len(data) > 0
    assert "date" in data[0]
    assert "emails_scanned" in data[0]

def test_subscriptions_crud_flow():
    # 1. List Subscriptions
    response_list = client.get("/api/v1/subscriptions")
    assert response_list.status_code == 200
    list_data = response_list.json()
    assert "subscriptions" in list_data
    assert list_data["active_count"] > 0
    assert list_data["monthly_spend"] > 0
    
    sub = list_data["subscriptions"][0]
    sub_id = sub["id"]
    
    # 2. Get Subscription Detail
    response_detail = client.get(f"/api/v1/subscriptions/{sub_id}")
    assert response_detail.status_code == 200
    detail_data = response_detail.json()
    assert "subscription" in detail_data
    assert "emails" in detail_data
    assert len(detail_data["emails"]) > 0
    
    # 3. Cancel Subscription
    response_cancel = client.post(f"/api/v1/subscriptions/{sub_id}/cancel")
    assert response_cancel.status_code == 200
    assert response_cancel.json()["status"] == "success"
    assert response_cancel.json()["subscription"]["status"] == "canceled"

def test_spend_insights():
    response = client.get("/api/v1/insights")
    assert response.status_code == 200
    data = response.json()
    assert "categories" in data
    assert "spend_trend" in data
    assert "Entertainment" in data["categories"]
    assert "Productivity" in data["categories"]
    assert len(data["spend_trend"]) > 0
