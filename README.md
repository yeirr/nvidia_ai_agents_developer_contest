# General Information

Instructions for running demo, change directory to project root before executing any
commands.

## Frontend

cd frontend/client
bash scripts/run_web.sh -r

Open web browser(Chrome mobile) and navigate to "http://localhost:8000"

## Backend

cd backend
fastapi dev server.py --port 8080
