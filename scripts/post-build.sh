#!/bin/bash
#
# Post-build phase — the gate.
#
# On success: push the trusted image to the registry (and optionally deploy).
# On failure: turn the opaque HTTP 403 into a human-readable verdict
#             (policy + condition + CVE IDs), then fail the pipeline so
#             nothing ships.
#
set -e

# Pick up ECR_URI computed in the pre-build phase.
source /tmp/build-env.sh

if [ "${CODEBUILD_BUILD_SUCCEEDING:-1}" = "1" ]; then
  # ==========================================================================
  # HAPPY PATH — every dependency was approved by Curation
  # ==========================================================================
  echo "=== STEP 3: push trusted image ==="
  docker push "${ECR_URI}:${IMAGE_TAG}"
  docker push "${ECR_URI}:latest"
  echo "PUSH SUCCESSFUL"

  # --- STEP 4 (optional): deploy the freshly pushed, trusted image ----------
  if [ -f ./scripts/deploy.sh ]; then
    echo "=== STEP 4: deploy ==="
    bash ./scripts/deploy.sh
  fi

  echo "PIPELINE COMPLETE — ${ECR_URI}:${IMAGE_TAG}"

else
  # ==========================================================================
  # BLOCKED PATH — Curation rejected a package; explain why, then fail
  # ==========================================================================
  echo "============================================"
  echo "BLOCKED BY JFROG CURATION"
  echo "============================================"

  # 1. Extract the offending package + version from pip's 403 in the build log.
  #    pip names the package in the failing URL, e.g.
  #    .../packages/.../<name>-<version>.tar.gz
  BLOCKED_PKG=$(grep -oP "HTTP error 403 while getting .*/packages/.*/\K[^/]+(?=#)" \
                  /tmp/docker-build.log 2>/dev/null | head -1 || true)
  PKG_NAME=$(echo "$BLOCKED_PKG" | sed 's/[-=<>!].*//')
  PKG_VERSION=$(echo "$BLOCKED_PKG" | grep -oP '[-=]{1,3}\K[0-9][^,; ]*' 2>/dev/null | head -1 || true)

  echo "  Package: ${PKG_NAME:-unknown}==${PKG_VERSION:-unknown}"

  # 2. Ask the Curation audit API which policy fired.
  #    Returns policy name, matched condition, and category.
  if [ -n "${PKG_NAME}" ]; then
    jf api "/xray/api/v1/curation/audit/packages?package_name=${PKG_NAME}&package_version=${PKG_VERSION}&num_of_rows=1" 2>/dev/null \
      | jq -r '.data[]?.policies[]? |
          "  Policy:    \(.policy_name)\n  Condition: \(.condition_name)\n  Category:  \(.condition_category)"' \
      || echo "  (audit API returned no policy detail)"
  fi

  # 3. Ask curation-audit for CVE IDs and a compliant recommendation.
  #    Requires "pass-through for Curation audit" enabled on the remote repo.
  if [ -n "${PKG_NAME}" ] && [ -n "${PKG_VERSION}" ]; then
    echo "${PKG_NAME}==${PKG_VERSION}" > /tmp/blocked-pkg.txt
    jf curation-audit --requirements-file=/tmp/blocked-pkg.txt --format=json 2>/dev/null \
      | jq -r '.[0].policies[]? | "  \(.explanation)\n  Recommendation: \(.recommendation)"' \
      || echo "  (curation-audit returned no CVE detail — is pass-through enabled?)"
    rm -f /tmp/blocked-pkg.txt
  fi

  echo "============================================"
  echo "PIPELINE FAILED — SKIPPING REGISTRY PUSH"
  echo "============================================"
  exit 1
fi
