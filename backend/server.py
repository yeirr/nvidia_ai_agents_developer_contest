import uuid
from pathlib import Path
from typing import Literal

from IPython.display import Image, display
from langchain.globals import set_debug, set_verbose
from langchain_core.messages import BaseMessage, HumanMessage
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from langgraph.checkpoint import MemorySaver
from langgraph.graph import END, MessageGraph
from langgraph.prebuilt import ToolNode

set_debug(False)
set_verbose(True)

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


@tool
def multiply_2(first_number: int, second_number: int):
    """Multiples two numbers together."""
    return first_number * second_number


def router(state: list[BaseMessage]) -> Literal["multiply_2", "__end__"]:
    tool_calls = state[-1].additional_kwargs.get("tool_calls", [])
    if len(tool_calls):
        return "multiply_2"
    else:
        return END


agent = ChatOpenAI(
    base_url="https://integrate.api.nvidia.com/v1",
    model_name="meta/llama3-8b-instruct",
    temperature=0.1,
    max_tokens=64,
    openai_api_key=Path("/home/yeirr/secret/ngc_personal_key.txt")
    .read_text()
    .strip("\n"),
    streaming=True,
)
agent_with_tools = agent.bind_tools(tools=[multiply_2])

# Define nodes
workflow = MessageGraph()
workflow.add_node("oracle", agent_with_tools)

tool_node = ToolNode([multiply_2])
workflow.add_node("multiply_2", tool_node)

# Build graph.
workflow.set_entry_point("oracle")
workflow.add_edge("multiply_2", END)
workflow.add_conditional_edges("oracle", router)
graph = workflow.compile(checkpointer=MemorySaver())

# Sanity check by visualizing graph.
display(
    Image(
        graph.get_graph(xray=True).draw_mermaid_png(
            output_file_path="/tmp/langgraph.png"
        )
    )
)

# Unique id to keep track of message threads during single session agent loop.
thread_id = str(uuid.uuid4())
config = {
    "configurable": {"uid": "123456", "thread_id": thread_id},
    "recursion_limit": 150,
}
while True:
    user = input("User (q/Q to quit): ")
    if user in {"q", "Q"}:
        print("AI: Byebye")
        break
    for output in graph.stream(
        [HumanMessage(content=user)],
        config=config,
    ):
        if "__end__" in output:
            continue
        # stream() yields dictionaries with output keyed by node name
        for key, value in output.items():
            print(f"Output from node '{key}':")
            print("---")
            print(value)
        print("\n---\n")
