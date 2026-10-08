#!/usr/bin/env bash

set -euo pipefail

npm run build
if [ -d ./server/web ]; then
    rm -rf ./server/web/*
fi
mkdir -p ./server/web
mv ./dist/* ./server/web

cd server
export UV_ENV_FILE=../.env
uv run fastapi dev