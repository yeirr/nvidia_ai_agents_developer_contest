from pathlib import Path

from openai import OpenAI

client = OpenAI(
    base_url="https://integrate.api.nvidia.com/v1",
    api_key=Path("/home/yeirr/secret/ngc_personal_key.txt").read_text().strip("\n"),
)

messages = [
    {
        "role": "system",
        "content": "You are a superhuman intelligent assistant, answer to the best of your abilities and do not make up answers.",
    },
    {
        "role": "user",
        "content": "hi there how are you?",
    },
]

completion = client.chat.completions.create(
    model="meta/llama3-8b-instruct",
    messages=messages,
    temperature=0.1,
    top_p=0.05,
    max_tokens=1024,
    stream=True,
)

buffer = []
for chunk in completion:
    if chunk.choices[0].delta.content is not None:
        print(chunk.choices[0].delta.content, end="")
        buffer.append(chunk.choices[0].delta.content)
    elif chunk.choices[0].finish_reason == "stop":
        pass

messages.append({"role": "assistant", "content": "".join(buffer)})
