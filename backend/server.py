import json
import re
import uuid
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import ORJSONResponse
from langchain_core.messages import HumanMessage
from langchain_core.runnables.config import RunnableConfig
from starlette.middleware import Middleware
from starlette_context import plugins
from starlette_context.middleware import RawContextMiddleware

from graph_implementation import graph


@asynccontextmanager
async def lifespan(app: FastAPI) -> Any:
    """Define logic using ASGI lifespan protocol on application events."""
    # Run startup operations.
    yield
    # Run clean up operations.


# Define list of routes.
origins = [
    # For development and quickfix.
    "http://localhost:8000",
]
# For daily builds and staging.
origin_regex = re.compile(
    r"(^https:\/\/(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.(carrd.co|web.app|firebaseapp.com|a.run.app){1,}\b$)"
)

middleware: list[Middleware] = [
    # Generate, tag or read request ID for each incoming request.
    Middleware(
        RawContextMiddleware,
        plugins=(plugins.RequestIdPlugin(),),
    ),
    # Cross-origin resource sharing configurations.
    Middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_origin_regex=origin_regex,
        # Origins must be specified if True.
        allow_credentials=True,
        allow_methods=["GET", "POST", "OPTIONS", "HEAD"],
        allow_headers=["*"],
        expose_headers=[],
    ),
]

app = FastAPI(
    title="ASGI web server",
    description="HTTP server for langgraph and nvidia NIM integration",
    swagger_ui_parameters={
        "tryItOutEnabled": True,
        "displayRequestDuration": True,
        "requestSnippetsEnabled": True,
    },
    version="v1alpha",
    middleware=middleware,
    lifespan=lifespan,
)


@app.post(
    "/generate",
    tags=["generate"],
    summary="Text inference endpoint",
    deprecated=False,
    status_code=status.HTTP_200_OK,
)
async def generate(request: Request) -> ORJSONResponse:
    try:
        request_body = await request.json()
        human_message = request_body["data"]["human_message"]
        # Unique id to keep track of message threads during single session agent loop.
        thread_id = str(uuid.uuid4())
        config: RunnableConfig = {
            "configurable": {"uid": "123456", "thread_id": thread_id},
        }
        # result = graph.invoke(
        # {
        # "messages": [HumanMessage(content=query)],
        # },
        # config=config,
        # )

        content = {
            "data": {
                "api_message": "LLM inference successful.",
                "human_message": human_message,
                # "ai_message": result["messages"][-1].content,
                "ai_message": str(uuid.uuid4()),
            }
        }
        return ORJSONResponse(content=content, status_code=status.HTTP_200_OK)
    except Exception:
        content = {
            "data": {
                "api_message": "LLM inference failed.",
                "human_message": human_message,
                "ai_message": "",
            }
        }
        return ORJSONResponse(
            content=content, status_code=status.HTTP_500_INTERNAL_SERVER_ERROR
        )
