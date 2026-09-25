#!/usr/bin/env bash
set -euo pipefail

# Supabase CLI 2.110.0 defaults to this registry. The E2E runner's isolated
# child environment drops registry overrides, so both jobs use that default.
if [[ "$(supabase --version)" != '2.110.0' ]]; then
  echo 'Pinned Supabase CLI version mismatch' >&2
  exit 1
fi
if [[ "${SUPABASE_INTERNAL_IMAGE_REGISTRY:-}" != 'public.ecr.aws' ]]; then
  echo 'Pinned Supabase image registry mismatch' >&2
  exit 1
fi

# The image set below matches the enabled services in this reviewed config.
# Fail closed if the config changes instead of leaving a new image to the
# CLI's concurrent missing-image pull path.
config='outputs/marketplace-production-foundation/supabase/config.toml'
if [[ "$(sha256sum "$config" | cut -d ' ' -f1)" != '46e79f7d8fd60ec92ba2531b5354aa84a2058cb6cfab4db43e204ba2832a5430' ]]; then
  echo 'Reviewed local Supabase config changed; update the image list' >&2
  exit 1
fi

images=(
  'postgres:15.8.1.085'
  'kong:2.8.1'
  'postgrest:v14.15'
  'gotrue:v2.193.0'
  'mailpit:v1.30.2'
  'realtime:v2.113.4'
  'storage-api:v1.66.4'
  'imgproxy:v3.8.0'
  'studio:2026.07.13-sha-b5ada96'
  'postgres-meta:v0.96.6'
)

for image in "${images[@]}"; do
  reference="public.ecr.aws/supabase/$image"
  docker pull --quiet "$reference" >/dev/null
  name="${image%%:*}"
  digests="$(docker image inspect --format '{{json .RepoDigests}}' "$reference")"
  if [[ ! "$digests" =~ public\.ecr\.aws/supabase/${name}@sha256:[a-f0-9]{64} ]]; then
    echo "Fresh pull lacked a verified registry digest: $name" >&2
    exit 1
  fi
  echo "Verified disposable image: $name"
done
