#!/bin/bash
set -euxo pipefail

VERSION="${1?No version passed}"
BASE_DIR=$(dirname "$(dirname "$(realpath -s "$0")")")

exec curl --follow -o "$BASE_DIR/components/gateway-api/gateway-api.yaml" "https://github.com/kubernetes-sigs/gateway-api/releases/download/v$VERSION/standard-install.yaml"
