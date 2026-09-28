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
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
