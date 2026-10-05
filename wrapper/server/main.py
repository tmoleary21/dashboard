from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

app = FastAPI()

app.mount("/", StaticFiles(directory="web", html=True), name="web")

@app.get("/api/hello")
def hello():
    return {"message": "Hello World"}

@app.get("/api/notifications")
def notifications():
    return []

# Server static files
# Detect notification files
# Allow queuing notification files throught API? Not necessary
