import json
import uuid
from datetime import datetime
from pathlib import Path
from typing import Annotated, Any, Dict, List, Literal, Optional

from IPython.display import Image, display
from langchain.globals import set_debug, set_verbose
from langchain_community.tools.tavily_search import TavilySearchResults
from langchain_community.utilities.tavily_search import TavilySearchAPIWrapper
from langchain_core.messages import AIMessage, HumanMessage, ToolMessage
from langchain_core.prompts import (
    ChatPromptTemplate,
    MessagesPlaceholder,
    PromptTemplate,
)
from langchain_core.pydantic_v1 import BaseModel
from langchain_core.runnables.config import RunnableConfig
from langchain_core.tools import ToolException, tool
from langchain_experimental.tools import PythonREPLTool
from langchain_openai import ChatOpenAI
from langgraph.checkpoint import MemorySaver
from langgraph.graph import END, StateGraph
from langgraph.graph.message import AnyMessage, add_messages

set_debug(False)
set_verbose(True)

# Done: vanilla langgraph react agent
# TODO: tools node with collection of tools
# TODO: main langgraph agent loop(retrieval, reflection, human-in-the-loop)
# TODO: specialized multi-agents(math,sci,law,biz)
# TODO: combination of SLMs(phi3-mini-4k), LLMs(llama3-8b), LMMs(llama3-70b)
#
# Accelerate multi-step problem-solving with a single generalist and multiple specialists.
# TODO: formulate problem and solution space
# TODO: track reasoning traces throughout the problem solving cycle
# TODO: eliminate logic flaws and implicit biases
# TODO: adopt historical personas(scientist, engineer, philosophers, leaders, educators)
# TODO: productivity goals and agent loop(research, assess, plan, action, evaluate, visualize, share)
# TODO: encourage problem-solvers to be novel problem seekers and think flexibly about the approach
tavily_api = TavilySearchAPIWrapper(
    tavily_api_key=Path("/home/yeirr/secret/tavily_api.txt")
    .read_text(
        encoding="utf-8",
    )
    .strip(),
)
tavily_tool = TavilySearchResults(api_wrapper=tavily_api, max_results=1)
python_repl_tool = PythonREPLTool()

tools = [tavily_tool]


# Supported models on NGC NIM endpoint.
# Text
# * "meta/llama3-8b-instruct"
# * "meta/llama3-70b-instruct"
# * "mistralai/mistral-large" supports tool call
# * "mistralai/mixtral-8x7b-instruct-v0.1"
# * "mistralai/mixtral-8x22b-instruct-v0.1" supports tool call
model = "meta/llama3-70b-instruct"
agent = ChatOpenAI(
    base_url="https://integrate.api.nvidia.com/v1",
    model=model,
    temperature=0.1,
    max_tokens=1024,
    api_key=Path("/home/yeirr/secret/ngc_personal_key.txt").read_text().strip("\n"),
)


def create_agent(llm: ChatOpenAI, tools: List[Any], system_message: str) -> Any:
    """Create an agent."""
    prompt = ChatPromptTemplate.from_messages(
        [
            (
                "system",
                "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n"
                "You are a helpful AI assistant, collaborating with other assistants."
                " Use the provided tools to progress towards answering the question."
                " If you are unable to fully answer, that's OK, another assistant with different tools "
                " will help where you left off. Execute what you can to make progress."
                " If you or any of the other assistants have the final answer or deliverable,"
                " prefix your response with FINAL ANSWER so the team knows to stop."
                " You have access to the following tools: {tool_names}.\n{system_message}"
                "<|eot_id|><|start_header_id|>user<|end_header_id|>",
            ),
            MessagesPlaceholder(variable_name="messages"),
        ]
    )
    prompt = prompt.partial(system_message=system_message)
    prompt = prompt.partial(tool_names=", ".join([tool.name for tool in tools]))
    return prompt | llm.bind_tools(tools)


# Leader node.
leader_prompt = PromptTemplate(
    template="""You are an expert at routing a user query to an action.
    Use websearch for generic queries.
    Give a binary choice 'action' or 'FINISH' based on the query. Return the a JSON with a single key 'action' and
    no premable or explanation. Query to route: {messages} """,
    input_variables=["messages"],
)

leader_agent = create_agent(llm=agent, tools=[], system_message=leader_prompt.template)


# Researcher node.
researcher_prompt = PromptTemplate(
    template="""You are an expert researcher in finding articles, news and the
    latest information pertaining to the following:
    {messages}
    """,
    input_variables=["messages"],
)

researcher_agent = create_agent(
    llm=agent, tools=[], system_message=researcher_prompt.template
)

# Programming node.
#
# THIS PERFORMS ARBITRARY CODE EXECUTION. PROCEED WITH CAUTION.
programmer_prompt = PromptTemplate(
    template="""You are an expert programmer who excels in solving programming problems
    pertaining to the following: 
    {messages}
    """,
    input_variables=["messages"],
)

programmer_agent = create_agent(
    llm=agent, tools=[], system_message=programmer_prompt.template
)


# The graph state is the input to each node in the graph.
class GraphState(BaseModel):
    messages: Annotated[list[AnyMessage], add_messages]


def call_tools_node(state: GraphState, config: RunnableConfig) -> Dict[str, Any]:
    messages = state.messages
    last_human_message = messages[-2].content
    print(f"TOOL_WEBSEARCH_INPUT: {last_human_message}")
    response = tavily_tool.invoke(
        last_human_message,
        max_tokens=1024,
        search_depth="advanced",
    )[0]["content"]
    print(f"TOOL_WEBSEARCH_RESPONSE: {response}")
    return {"messages": [ToolMessage(content=response, tool_call_id=str(uuid.uuid4()))]}


def call_leader_node(state: GraphState, config: RunnableConfig) -> Dict[str, Any]:
    messages = state.messages
    # New messages list.
    if len(messages) < 2:
        last_human_message = messages[0].content
        print(f"LEADER_NODE_INPUT_NEW: {last_human_message}")
        response = leader_agent.invoke(
            {"messages": [HumanMessage(content=last_human_message)]}
        )
        print(f"LEADER_RESPONSE: {response}")
        return {"messages": [response]}
    else:
        last_human_message = messages[-2].content
        print(f"LEADER_NODE_INPUT_EXISTING: {last_human_message}")
        response = leader_agent.invoke(
            {"messages": [HumanMessage(content=last_human_message)]}
        )
        print(f"LEADER_RESPONSE: {response}")
        return {"messages": [response]}


def call_researcher_node(state: GraphState, config: RunnableConfig) -> Dict[str, Any]:
    messages = state.messages
    last_human_message = messages[-2].content
    print(f"RESEARCHER_NODE_INPUT: {last_human_message}")
    if last_human_message == "y":
        return {
            "messages": [state.tool_call_message],
            "tool_call_message": None,
        }

    else:
        response = researcher_agent.invoke(
            {"messages": [HumanMessage(content=last_human_message)]}
        )
        print(f"RESEARCHER_RESPONSE: {response.content}")
        if response.tool_calls:
            verification_message = generate_verification_message(response)
            response.id = str(uuid.uuid4())
            return {"messages": [verification_message], "tool_call_message": response}
        else:
            return {"messages": [response], "tool_call_message": None}


def call_programmer_node(state: GraphState, config: RunnableConfig) -> Dict[str, Any]:
    messages = state.messages
    last_human_message = messages[-2].content
    print(f"PROGRAMMER_NODE_INPUT: {last_human_message}")
    response = programmer_agent.invoke(
        {"messages": [HumanMessage(content=last_human_message)]}
    )
    print(f"PROGRAMMER_RESPONSE: {response}")
    # We return a list, because this will get added to the existing list
    return {"messages": [response]}


# Define nodes
def route_query(state: GraphState, config: RunnableConfig) -> str:
    """
    Route query to specialists.

    Args:
        state (dict): The current graph state

    Returns:
        str: Next node to call
    """

    print("---ROUTE QUERY---")
    messages = state.messages
    last_message = str(messages[-1].content)  # Target AIMessage
    route = json.loads(last_message)
    if route["specialist"] == "researcher":
        print("---ROUTE QUERY TO RESEARCHER---")
        return "researcher"
    elif route["specialist"] == "programmer":
        print("---ROUTE QUERY TO PROGRAMMER---")
        return "programmer"
    else:
        return "FINISH"


def should_action(state: GraphState, config: RunnableConfig) -> str:
    """
    Route query to tools.

    Args:
        state (dict): The current graph state

    Returns:
        str: Next node to call
    """

    print("---ROUTE ACTIONS---")
    messages = state.messages
    last_message = str(messages[-1].content)
    route = json.loads(last_message)
    if route["action"] == "websearch":
        print("---ROUTE QUERY to ACTION---")
        return "action"
    else:
        return "FINISH"


# Compile workflow graph.
workflow = StateGraph(GraphState)
workflow.add_node("action", call_tools_node)
workflow.add_node("leader", call_leader_node)
# workflow.add_node("researcher", call_researcher_node)
# workflow.add_node("programmer", call_programmer_node)

# Build graph.
workflow.set_entry_point("leader")
workflow.add_conditional_edges(
    "leader", should_action, {"action": "action", "FINISH": END}
)
workflow.add_edge("action", "leader")
# workflow.add_edge("programmer", END)
checkpointer = MemorySaver()
graph = workflow.compile(checkpointer=checkpointer)

# Sanity checks by visualizing graph(with nested structures) and running warmup inference.
display(
    Image(
        graph.get_graph(xray=True).draw_mermaid_png(
            output_file_path="/tmp/llm_workflow.png"
        )
    )
)
uid = str(uuid.uuid4())
thread_id = str(uuid.uuid4())
config: RunnableConfig = {
    "recursion_limit": 150,
    "configurable": {"thread_id": thread_id, "uid": uid},  # runtime values
}
for event in graph.stream(
    {"messages": [HumanMessage(content="who is michelle obama?")]},
    config,
    stream_mode="values",
):
    event["messages"][-1].pretty_print()

# Record and parse thread creation isoformat to utc timestamp.
thread_isoformat = graph.get_state(
    {"configurable": {"thread_id": thread_id}}
).created_at
thread_timestamp_utc = datetime.fromisoformat(thread_isoformat).timestamp()
