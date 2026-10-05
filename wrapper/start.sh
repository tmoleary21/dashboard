#!/usr/bin/env bash

set -euo pipefail

if [ ! -d ./env ]; then
    python3 -m venv env
fi

source ./env/bin/activate

pip install -r ./requirements.txt

python -m server