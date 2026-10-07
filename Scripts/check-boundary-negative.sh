#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/check-source-boundaries.sh
python3 Scripts/check-boundaries.py
python3 -m unittest discover -s Tests/Governance -p 'test_*.py' -v
python3 Scripts/check-compiler-boundary.py
