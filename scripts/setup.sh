#!/bin/bash
#
# Pre-build phase.
#
# 1. Install the JFrog CLI.
# 2. Authenticate to JFrog and to the container registries.
# 3. Point pip at the curated JFrog repository so EVERY pip install
#    (including the ones inside the Docker build) is gated by Curation.
#
set -euo pipefail

echo "=== STEP 1: pre-build setup ==="

# --- Install the JFrog CLI --------------------------------------------------
curl -fL https://install-cli.jfrog.io | sh

# --- Register the JFrog server using the token from Secrets Manager ---------
jf config add jfrog-server \
  --url="https://${JFROG_HOST}" \
  --access-token="${JFROG_TOKEN}" \
  --interactive=false
jf config use jfrog-server

# --- Point pip at the curated repo instead of public PyPI -------------------
# This writes a pip config that swaps the default index URL (pypi.org) for the
# JFrog virtual repo. From here on, pip asks Artifactory for packages, and
# Artifactory returns HTTP 403 for anything a Curation policy blocks.
jf pip-config \
  --repo-resolve="${JFROG_REPO}" \
  --server-id-resolve=jfrog-server

# --- Authenticate to Amazon ECR (destination for the trusted image) ---------
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" \
  | docker login --username AWS --password-stdin \
      "${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
echo "ECR login successful"

# --- Authenticate to the JFrog Docker registry -----------------------------
# (only needed if base images are pulled through JFrog)
echo "${JFROG_TOKEN}" | docker login "${JFROG_HOST}" -u "${JFROG_USER}" --password-stdin
echo "JFrog Docker login successful"

# --- Share derived values with later phases ---------------------------------
# Each `bash ./scripts/*.sh` runs in its own subshell, so exported vars do NOT
# survive to the next phase. Write them to a file that later scripts source.
cat > /tmp/build-env.sh <<EOF
export PIP_PROXY="https://${JFROG_USER}:${JFROG_TOKEN}@${JFROG_HOST}/artifactory/api/pypi/${JFROG_REPO}/simple"
export ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ECR_REPO}"
EOF
echo "Wrote /tmp/build-env.sh for later phases"
