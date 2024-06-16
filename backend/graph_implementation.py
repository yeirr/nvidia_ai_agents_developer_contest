import json
import uuid
from datetime import datetime
from json import JSONDecodeError
from pathlib import Path
from typing import Annotated, Any, Dict, List, Union

from langchain.globals import set_debug, set_verbose
from langchain_core.messages import AIMessage, HumanMessage
from langchain_core.prompts import (
    ChatPromptTemplate,
    MessagesPlaceholder,
    PromptTemplate,
)
from langchain_core.pydantic_v1 import BaseModel
from langchain_core.runnables.config import RunnableConfig
from langchain_openai import ChatOpenAI
from langgraph.checkpoint import MemorySaver
from langgraph.graph import END, StateGraph
from langgraph.graph.message import AnyMessage, add_messages

set_debug(False)
set_verbose(True)

# Done: vanilla langgraph react agent
# Done: tools node with collection of tools
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


# Supported text models on NGC NIM endpoint.
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
    template="""You are an expert at routing a user query to a specialist.
    Use biology for biological related queries.
    Use physiology for physiological related queries.
    Use math for math related queries.
    Use engineer for engineering related queries.
    Use psychology for psychology related queries.
    Given a binary choice of 'next', 'FINISH' based on the query. 

    Examples:

    ```python
    {\"supervisor\": {\"next\": \"biology\"}}
    {\"supervisor\": {\"next\": \"physiology\"}}
    {\"supervisor\": {\"next\": \"math\"}}
    {\"supervisor\": {\"next\": \"engineer\"}}
    {\"supervisor\": {\"next\": \"psychology\"}}
    {\"supervisor\": {\"next": \"FINISH\"}}
    ```
    Return the a JSON with a single key 'supervisor', a nested key 'next' and no premable or explanation. Query to route: {messages} """,
    input_variables=["messages"],
)

leader_agent = create_agent(llm=agent, tools=[], system_message=leader_prompt.template)


# Biology node.
biology_prompt = PromptTemplate(
    template="""You adopt the persona of Charles Robert Darwin, a English naturalist,
    geologist and biologist. You are also up-to-date with the entire biology field, the
    scientific study of life. You are able to study life at multiple levels of
    organization, from the molecular biology of a cell to the anatomy and physiology of
    plants and animals, and evolution of populations. You are an expert at utilizing the
    scientific method to make observations, pose questions generate hypotheses, perform
    experiments, and form conclusions about the world around them.

    Answer the following queries in his tone and personality:
    {messages}
    """,
    input_variables=["messages"],
)

biology_agent = create_agent(
    llm=agent, tools=[], system_message=biology_prompt.template
)

# Physiology node.
physiology_prompt = PromptTemplate(
    template="""You adopt the persona of Claude Bernard, a French physiologist known for
    his work on the concept of homeostasis.

    Answer the following queries in his tone and personality:
    {messages}
    """,
    input_variables=["messages"],
)

physiology_agent = create_agent(
    llm=agent, tools=[], system_message=physiology_prompt.template
)

# Math node.
math_prompt = PromptTemplate(
    template="""You adopt the persona of Leonhard Euler, a mathematician, physicist,
    astronomer, geographer, logician and engineer.

    Answer the following queries in his tone and personality:
    {messages}
    """,
    input_variables=["messages"],
)
math_agent = create_agent(llm=agent, tools=[], system_message=math_prompt.template)

# Engineer node.
engineer_prompt = PromptTemplate(
    template="""You adopt the persona of Leonardo di ser Piero da Vinci, n Italian
    polymath of the High Renaissance who was active as a painter, draughtsman, engineer,
    scientist, theorist, sculptor, and architect. 

    Answer the following queries in his tone and personality:
    {messages}
    """,
    input_variables=["messages"],
)
engineer_agent = create_agent(
    llm=agent, tools=[], system_message=engineer_prompt.template
)

# Psychology node.
psychology_prompt = PromptTemplate(
    template="""You adopt the persona of Wilhelm Maximilian Wundt, a German
    physiologist, philosopher, and professor, one of the fathers of modern psychology.

    Answer the following queries in his tone and personality:
    {messages}
    """,
    input_variables=["messages"],
)
psychology_agent = create_agent(
    llm=agent, tools=[], system_message=psychology_prompt.template
)


# The graph state is the input to each node in the graph.
class GraphState(BaseModel):
    messages: Annotated[list[AnyMessage], add_messages]


def call_leader_node(
    state: GraphState, config: RunnableConfig
) -> Union[Dict[str, Any], str]:
    query = config["configurable"]["query"]
    print(f"LEADER_NODE_INPUT: {query}")
    response = leader_agent.invoke({"messages": [HumanMessage(content=query)]})
    return {"messages": [response]}


def call_biology_node(state: GraphState, config: RunnableConfig) -> Dict[str, Any]:
    query = config["configurable"]["query"]
    print(f"BIOLOGY_NODE_INPUT: {query}")
    response = biology_agent.invoke({"messages": [HumanMessage(content=query)]})
    return {"messages": [AIMessage(content=response.content)]}


def call_physiology_node(state: GraphState, config: RunnableConfig) -> Dict[str, Any]:
    query = config["configurable"]["query"]
    print(f"PHYSIOLOGY_NODE_INPUT: {query}")
    response = physiology_agent.invoke({"messages": [HumanMessage(content=query)]})
    return {"messages": [AIMessage(content=response.content)]}


def call_math_node(state: GraphState, config: RunnableConfig) -> Dict[str, Any]:
    query = config["configurable"]["query"]
    print(f"MATH_NODE_INPUT: {query}")
    response = math_agent.invoke({"messages": [HumanMessage(content=query)]})
    return {"messages": [AIMessage(content=response.content)]}


def call_engineer_node(state: GraphState, config: RunnableConfig) -> Dict[str, Any]:
    query = config["configurable"]["query"]
    print(f"ENGINEER_NODE_INPUT: {query}")
    response = engineer_agent.invoke({"messages": [HumanMessage(content=query)]})
    return {"messages": [AIMessage(content=response.content)]}


def call_psychology_node(state: GraphState, config: RunnableConfig) -> Dict[str, Any]:
    query = config["configurable"]["query"]
    print(f"PSYCHOLOGY_NODE_INPUT: {query}")
    response = psychology_agent.invoke({"messages": [HumanMessage(content=query)]})
    return {"messages": [AIMessage(content=response.content)]}


# Define nodes
def route_query(state: GraphState, config: RunnableConfig) -> str:
    """
    Route query to specialists.

    Args:
        state (dict): The current graph state

    Returns:
        str: Next node to call
    """

    messages = state.messages
    last_message = str(messages[-1].content)  # Target AIMessage
    print(f"ROUTE_QUERY_INPUT: {last_message}")
    route = json.loads(last_message)
    if route["supervisor"]["next"] == "biology":
        print("---ROUTE QUERY TO BIOLOGY NODE---")
        return "biology"
    elif route["supervisor"]["next"] == "physiology":
        print("---ROUTE QUERY TO PHYSIOLOGY NODE---")
        return "physiology"
    elif route["supervisor"]["next"] == "math":
        print("---ROUTE QUERY TO MATH NODE---")
        return "math"
    elif route["supervisor"]["next"] == "engineer":
        print("---ROUTE QUERY TO ENGINEER NODE---")
        return "engineer"
    elif route["supervisor"]["next"] == "psychology":
        print("---ROUTE QUERY TO PSYCHOLOGY NODE---")
        return "psychology"
    elif route["supervisor"]["next"] == "FINISH":
        return "FINISH"


# Compile workflow graph.
workflow = StateGraph(GraphState)
workflow.add_node("leader", call_leader_node)
workflow.add_node("biology", call_biology_node)
workflow.add_node("physiology", call_physiology_node)
workflow.add_node("math", call_math_node)
workflow.add_node("engineer", call_engineer_node)
workflow.add_node("psychology", call_psychology_node)

# Build graph.
workflow.set_entry_point("leader")
workflow.add_conditional_edges(
    "leader",
    route_query,
    {
        "FINISH": END,
        "biology": "biology",
        "physiology": "physiology",
        "math": "math",
        "engineer": "engineer",
        "psychology": "psychology",
    },
)
workflow.add_edge("biology", END)
workflow.add_edge("physiology", END)
workflow.add_edge("math", END)
workflow.add_edge("engineer", END)
workflow.add_edge("psychology", END)
checkpointer = MemorySaver()
graph = workflow.compile(checkpointer=checkpointer)


# Sanity checks by visualizing graph(with nested structures) and running warmup inference.
def sanity_check() -> None:
    graph.get_graph(xray=True).draw_png(output_file_path="/tmp/workflow.png")
    uid = str(uuid.uuid4())
    thread_id = str(uuid.uuid4())
    query = "can you explain basic psychology concepts to a five year old?"
    config: RunnableConfig = {
        "recursion_limit": 150,
        "configurable": {
            "thread_id": thread_id,
            "uid": uid,
            "query": query,
        },
    }
    for event in graph.stream(
        {"messages": [HumanMessage(content=query)]},
        config,
        stream_mode="values",
    ):
        event["messages"][-1].pretty_print()

    # Record and parse thread creation isoformat to utc timestamp.
    thread_isoformat = graph.get_state(
        {"configurable": {"thread_id": thread_id}}
    ).created_at
    thread_timestamp_utc = datetime.fromisoformat(thread_isoformat).timestamp()
