import json
import uuid
from datetime import datetime
from pathlib import Path
from typing import Annotated, Any, Dict, List, Literal, Optional

from IPython.display import Image, display
from langchain_community.tools.tavily_search import TavilySearchResults
from langchain_community.utilities.tavily_search import TavilySearchAPIWrapper
from langchain_core.messages import AIMessage, HumanMessage
from langchain_core.prompts import (
    ChatPromptTemplate,
    MessagesPlaceholder,
    PromptTemplate,
)
from langchain_core.pydantic_v1 import BaseModel
from langchain_core.runnables.config import RunnableConfig
from langchain_core.tools import tool
from langchain_experimental.tools import PythonREPLTool
from langchain_openai import ChatOpenAI
from langgraph.checkpoint import MemorySaver
from langgraph.graph import END, StateGraph
from langgraph.graph.message import AnyMessage, add_messages
from langgraph.prebuilt import ToolNode

# Done: vanilla langgraph react agent
# TODO: main langgraph agent loop(retrieval, reflection, human-in-the-loop)
# TODO: specialized multi-agents(websearch,math,sci,law,biz)
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
tavily_tool = TavilySearchResults(api_wrapper=tavily_api, max_results=3)
python_repl_tool = PythonREPLTool()


@tool
def web_search(query: str) -> List[str]:
    """Placeholder for implementation."""
    return ["The weather is cloudy with a chance of meatballs."]


tools = [web_search]
tools_node = ToolNode(tools)


# Supported models on NGC NIM endpoint.
# Text
# * "meta/llama3-8b-instruct"
# * "meta/llama3-70b-instruct"
# * "mistralai/mistral-large"
# * "mistralai/mixtral-8x7b-instruct-v0.1"
# * "mistralai/mixtral-8x22b-instruct-v0.1"
model = "meta/llama3-70b-instruct"
agent = ChatOpenAI(
    base_url="https://integrate.api.nvidia.com/v1",
    model=model,
    temperature=0.1,
    max_tokens=32,
    api_key=Path("/home/yeirr/secret/ngc_personal_key.txt").read_text().strip("\n"),
)


def create_agent(llm: ChatOpenAI, tools: List[Any], system_message: str) -> Any:
    """Create an agent."""
    prompt = ChatPromptTemplate.from_messages(
        [
            (
                "system",
                "You are a helpful AI assistant, collaborating with other assistants."
                " Use the provided tools to progress towards answering the question."
                " If you are unable to fully answer, that's OK, another assistant with different tools "
                " will help where you left off. Execute what you can to make progress."
                " If you or any of the other assistants have the final answer or deliverable,"
                " prefix your response with FINAL ANSWER so the team knows to stop."
                " You have access to the following tools: {tool_names}.\n{system_message}",
            ),
            MessagesPlaceholder(variable_name="messages"),
        ]
    )
    prompt = prompt.partial(system_message=system_message)
    prompt = prompt.partial(tool_names=", ".join([tool.name for tool in tools]))
    return prompt | llm.bind_tools(tools)


# Leader node.
leader_prompt = PromptTemplate(
    template="""You are an expert at routing a user query to a specialist.
    Use the researcher for generic queries and programmer for programming queries.
    Give a binary choice 'researcher' or 'programmer' based on the query. Return the a JSON with a single key 'specialist' and 
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
    llm=agent, tools=tools, system_message=researcher_prompt.template
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
    tool_call_message: Optional[AIMessage]


# Utility function to construct message asking for verification.
def generate_verification_message(message: AIMessage) -> AIMessage:
    """Generate "verification message" from message with tool calls."""
    serialized_tool_calls = json.dumps(
        message.tool_calls,
        indent=2,
    )
    return AIMessage(
        content=(
            "I plan to invoke the following tools, do you approve?\n\n"
            "Type 'y' if you do, anything else to stop.\n\n"
            f"{serialized_tool_calls}"
        ),
        id=message.id,
    )


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
        last_human_message = messages[-1].content
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


# Define the function that determines whether to continue or not.
def should_continue(state: GraphState) -> Literal["continue", "FINISH"]:
    last_message = state.messages[-1]
    # If there is no function call, then we finish.
    if not last_message.tool_calls:
        return "FINISH"
    # Otherwise if there is, we continue.
    else:
        return "continue"


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


# Compile workflow graph.
workflow = StateGraph(GraphState)
workflow.add_node("action", tools_node)
workflow.add_node("leader", call_leader_node)
workflow.add_node("researcher", call_researcher_node)
workflow.add_node("programmer", call_programmer_node)

# Build graph.
workflow.set_entry_point("leader")
workflow.add_conditional_edges(
    "leader",
    route_query,
    {
        "FINISH": END,
        "researcher": "researcher",
        "programmer": "programmer",
    },
)
workflow.add_conditional_edges(
    "researcher", should_continue, {"continue": "action", "FINISH": END}
)
workflow.add_edge("action", "researcher")
workflow.add_edge("programmer", END)
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
print(
    graph.invoke(
        {
            "messages": [
                HumanMessage(content="who is benjamin buttons?"),
            ]
        },
        config=config,
    )["messages"][-1].content
)
# Record and parse thread creation isoformat to utc timestamp.
thread_isoformat = graph.get_state(
    {"configurable": {"thread_id": thread_id}}
).created_at
thread_timestamp_utc = datetime.fromisoformat(thread_isoformat).timestamp()
