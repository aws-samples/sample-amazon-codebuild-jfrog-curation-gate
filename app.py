"""Minimal sample app.

Its only job is to give the container something to run so the pipeline
produces a real, runnable image. The point of the sample is the CI/CD
Curation gate, not this app.
"""

from fastapi import FastAPI

app = FastAPI(title="Curated Sample App")


@app.get("/")
def root():
    return {"status": "ok", "message": "Built through a JFrog Curation gate."}


@app.get("/health")
def health():
    return {"status": "healthy"}


if __name__ == "__main__":
    import os

    import uvicorn

    # Bind address is configurable via APP_HOST. The default is 0.0.0.0 because
    # this runs as a containerized service: the process must listen on all
    # interfaces inside the container for the published port to be reachable.
    # Isolation is provided by the container/network boundary, not by binding
    # to loopback. Override APP_HOST (e.g. 127.0.0.1) for a local-only bind.
    host = os.getenv("APP_HOST", "0.0.0.0")  # nosec B104
    port = int(os.getenv("APP_PORT", "8080"))
    uvicorn.run(app, host=host, port=port)
