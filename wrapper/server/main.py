import os
import sys
from fastapi import FastAPI
from fastapi.responses import PlainTextResponse
from fastapi.staticfiles import StaticFiles
from notifications.notifications import collect_notifications, delete_notification

def load_env():
    variables = { # Variable name to default value
        "WRAPPED_SITE": "http://localhost:5174",
        "NOTIFICATIONS_DROP_DIR": "notifications",
        "WEB_DIR": "web"
    }

    print()
    print("=== Environment setup ===")
    for name, default in variables.items():
        variables[name] = os.getenv(name, default)
        print(f"{name}={variables[name]}")

    print()

    return variables

env = load_env()

app = FastAPI()

@app.get("/api/hello")
def hello():
    return {"message": "Hello World"}

@app.get("/api/wrapped", response_class=PlainTextResponse)
def get_wrapped_site():
    return env["WRAPPED_SITE"]

@app.get("/api/notifications")
def notifications():
    return collect_notifications(env["NOTIFICATIONS_DROP_DIR"])

@app.post("/api/notifications/dismiss/{id}")
def dismiss_notification(id: str):
    delete_notification(id)

app.mount("/", StaticFiles(directory=env["WEB_DIR"], html=True), name="web")
