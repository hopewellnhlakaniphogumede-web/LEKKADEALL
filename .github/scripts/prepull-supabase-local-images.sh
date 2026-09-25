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

image_config_digest() {
  local reference="$1" manifest platform_digest config_digest
  manifest="$(docker buildx imagetools inspect --raw "$reference" 2>/dev/null)" || return 1
  if [[ "$(jq -r 'has("manifests")' <<< "$manifest")" == 'true' ]]; then
    platform_digest="$(jq -r '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64" and (.platform.variant // "") == "") | .digest] | if length == 1 then .[0] else empty end' <<< "$manifest")" || return 1
    [[ "$platform_digest" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
    manifest="$(docker buildx imagetools inspect --raw "${reference%:*}@$platform_digest" 2>/dev/null)" || return 1
  fi
  config_digest="$(jq -er '.config.digest | select(type == "string")' <<< "$manifest")" || return 1
  [[ "$config_digest" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
  printf '%s' "$config_digest"
}

if [[ "${1:-}" == '--compare-identities' ]]; then
  if [[ "$(uname -s)" != 'Linux' || "$(uname -m)" != 'x86_64' ]]; then
    echo 'Supabase image identity: UNRESOLVED (runner platform)' >&2
    exit 1
  fi
  for image in "${images[@]}"; do
    name="${image%%:*}"
    ecr_reference="public.ecr.aws/supabase/$image"
    ghcr_reference="ghcr.io/supabase/$image"
    if ! local_id="$(docker image inspect --format '{{.Id}}' "$ecr_reference" 2>/dev/null)" \
      || ! ecr_id="$(image_config_digest "$ecr_reference")" \
      || ! ghcr_id="$(image_config_digest "$ghcr_reference")"; then
      echo "Supabase image identity $name: UNRESOLVED" >&2
      exit 1
    fi
    if [[ ! "$local_id" =~ ^sha256:[a-f0-9]{64}$ || "$local_id" != "$ecr_id" || "$ecr_id" != "$ghcr_id" ]]; then
      echo "Supabase image identity $name: MISMATCH" >&2
      exit 1
    fi
    if [[ "$name" == 'postgres' ]]; then
      if ! running_id="$(docker container inspect --format '{{.Image}}' supabase_db_lekkadeall-local 2>/dev/null)"; then
        echo 'Supabase image identity postgres: UNRESOLVED' >&2
        exit 1
      fi
      if [[ "$running_id" != "$local_id" ]]; then
        echo 'Supabase image identity postgres: MISMATCH' >&2
        exit 1
      fi
    fi
    echo "Supabase image identity $name: MATCH"
  done
  exit 0
elif [[ $# -ne 0 ]]; then
  echo 'Unsupported Supabase image helper mode' >&2
  exit 1
fi

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
