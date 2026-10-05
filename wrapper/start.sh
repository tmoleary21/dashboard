#!/usr/bin/env bash

set -euo pipefail

npm run build

cd server
export UV_ENV_FILE=../.env
uv run fastapi dev