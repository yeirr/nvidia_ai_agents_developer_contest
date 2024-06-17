# General Information

Instructions for running demo, change directory to project root before executing any
commands.

## Frontend

* cd frontend/client
* install Flutter SDK for your OS(instructions at "https://docs.flutter.dev/get-started/install")
* bash scripts/run_web.sh -r
* open web browser(Chrome mobile) and navigate to "http://localhost:8000"

## Backend

* cd backend
* pip install -r requirements.txt
* fastapi dev server.py --port 8080
