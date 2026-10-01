#!/bin/bash
#
# Build phase.
#
# Runs the Docker build THROUGH the JFrog CLI so the build and its resolved
# dependencies are recorded in JFrog. The curated index URL is passed down as
# a build arg, so the `pip install` inside the Dockerfile is what gets gated.
#
set -o pipefail

# Pick up PIP_PROXY / ECR_URI computed in the pre-build phase.
source /tmp/build-env.sh

echo "=== STEP 2: curated docker build ==="

# Tee the full output to a log file. The post-build gate parses this log to
# extract the block reason if Curation rejects a package.
jf docker build --no-cache \
  --build-arg PIP_INDEX_URL="${PIP_PROXY}" \
  --build-arg PIP_TRUSTED_HOST="${JFROG_HOST}" \
  -t "${ECR_URI}:${IMAGE_TAG}" . 2>&1 | tee /tmp/docker-build.log

# IMPORTANT: read the exit code of the BUILD, not of `tee`.
# Because the build is piped into tee, `$?` would be tee's exit code (0),
# masking a failed build. PIPESTATUS[0] is the first command's real exit code.
# This is why buildspec.yml forces `shell: bash` — `sh` has no PIPESTATUS.
BUILD_EXIT=${PIPESTATUS[0]}

if [ "$BUILD_EXIT" -eq 0 ]; then
  docker tag "${ECR_URI}:${IMAGE_TAG}" "${ECR_URI}:latest"
  echo "============================================"
  echo "DOCKER BUILD SUCCESSFUL"
  echo "ALL DEPENDENCIES APPROVED BY JFROG CURATION"
  echo "============================================"
else
  # A blocked package -> HTTP 403 -> pip fails -> RUN layer fails ->
  # jf docker build exits non-zero. Fail the build so CodeBuild sets
  # CODEBUILD_BUILD_SUCCEEDING=0, which the post-build gate keys off.
  echo "Build failed (exit $BUILD_EXIT) — see post-build for the block reason"
  exit 1
fi
