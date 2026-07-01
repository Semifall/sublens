from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.routers import router as api_router
import uvicorn

APP_VERSION = "1.0.0"

app = FastAPI(
    title="Sublens Backend API",
    description="Stateless scanner backend for Subscription Guard (Sublens)",
    version=APP_VERSION
)

# Configure CORS for local development and app integration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8080", "http://127.0.0.1:8080"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def on_startup():
    from app.api.routers import seed_mock_data
    seed_mock_data()

# Root status check
@app.get("/")
async def root():
    return {
        "app": "Sublens Backend API",
        "status": "healthy",
        "version": APP_VERSION
    }

# Include API Router
app.include_router(api_router)

if __name__ == "__main__":
    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True)
