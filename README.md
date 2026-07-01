# SubLens — Subscription Guard

SubLens helps you discover, track, and manage all your recurring subscriptions automatically from your email history. Know every subscription, save every dollar.

---

## 🛠️ Tech Stack & Structure

- **Backend**: Python 3.11+, FastAPI, Uvicorn, Pydantic, PyJWT (JSON Web Token), PyYAML
- **Frontend**: Flutter Web / Mobile, Custom Canvas / Painters, AppLocalizations (English & Chinese)
- **Shared**: Configuration rules (`shared/merchant_rules/rules.yaml`) for rule-based matching

### Directory Layout
```text
F:/AI/sublens/
├── backend/            # FastAPI Python server application
│   ├── app/            # Source code (routers, recognizers, models)
│   ├── requirements.txt # Production dependencies
│   └── requirements-dev.txt # Development & testing dependencies
├── mobile/             # Flutter mobile & web application client
│   ├── lib/            # Dart implementation files (ui, models, localizations)
│   └── pubspec.yaml    # Flutter dependency configuration
├── shared/             # Configurations shared between services
└── tests/              # Pytest automated test suite
```

---

## 🚀 Running Locally

### 1. Backend Server Setup

Ensure you are inside the virtual environment:
```bash
# From F:/AI/sublens
.venv\Scripts\activate

# Install dependencies
pip install -r backend/requirements.txt
```

Start the FastAPI application on local port `8000`:
```bash
# From F:/AI/sublens/backend
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

#### Environment Variables
- `JWT_SECRET`: Secret key used for encoding/decoding auth JWT tokens.
- `DEEPSEEK_API_KEY`: API key for calling DeepSeek LLM for category parsing.

### 2. Frontend Client Setup

Make sure you have Flutter installed. Navigate to the mobile directory:
```bash
cd F:/AI/sublens/mobile
flutter pub get
```

Start the Flutter development server (web-server):
```bash
flutter run -d web-server --web-port 8080 --web-hostname 127.0.0.1
```

Access the app in your browser at `http://127.0.0.1:8080`.

---

## 🧪 Testing

### Backend Unit Tests
Run backend tests using `pytest`:
```bash
# From F:/AI/sublens
.venv\Scripts\python.exe -m pytest tests/ -v
```

### Frontend Widget Tests
Run flutter unit/widget tests:
```bash
# From F:/AI/sublens/mobile
flutter test
```
