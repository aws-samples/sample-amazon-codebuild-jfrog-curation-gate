# Generic sample image.
#
# The security gate happens on the `pip install -r requirements.txt` line:
# when PIP_INDEX_URL points at the curated JFrog repo, every package is
# evaluated by Curation and a blocked package fails this build.

# Base image is pulled from ECR Public (not Docker Hub) so the build does not
# depend on an external/uncontrolled registry.
FROM public.ecr.aws/docker/library/python:3.11-slim

# Passed in by scripts/docker-build.sh (the curated JFrog index URL).
ARG PIP_INDEX_URL
ARG PIP_TRUSTED_HOST

WORKDIR /app

COPY requirements.txt .

# Upgrade pip itself from public PyPI (pip is not the curated surface here)…
RUN pip install --no-cache-dir --upgrade pip --index-url https://pypi.org/simple && \
    # …then install ALL app dependencies through the curated JFrog repo.
    # The if/else lets the same Dockerfile build locally (no build args) while
    # always going through JFrog in CI (build args present).
    if [ -n "$PIP_INDEX_URL" ] && [ -n "$PIP_TRUSTED_HOST" ]; then \
      pip install --no-cache-dir --index-url "$PIP_INDEX_URL" --trusted-host "$PIP_TRUSTED_HOST" -r requirements.txt; \
    else \
      pip install --no-cache-dir -r requirements.txt; \
    fi

COPY app.py .

EXPOSE 8080
CMD ["python", "app.py"]
