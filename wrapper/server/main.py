import os
import sys
from fastapi import FastAPI
from fastapi.responses import PlainTextResponse
from fastapi.staticfiles import StaticFiles
from notifications.notifications import collect_notifications, delete_notification

app = FastAPI()

@app.get("/api/hello")
def hello():
    return {"message": "Hello World"}

@app.get("/api/wrapped", response_class=PlainTextResponse)
def get_wrapped_site():
    return os.getenv("WRAPPED_SITE", "http://localhost:5174")

@app.get("/api/notifications")
def notifications():
    return collect_notifications(os.getenv("NOTIFICATIONS_DROP_DIR", "notifications"))

@app.post("/api/notifications/dismiss/{id}")
def dismiss_notification(id: str):
    delete_notification(id)

app.mount("/", StaticFiles(directory=os.getenv("WEB_DIR", "web"), html=True), name="web")
