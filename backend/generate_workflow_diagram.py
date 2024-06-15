from anytree import Node, RenderTree
from anytree.exporter import UniqueDotExporter

start = Node("start")
leader = Node("leader", parent=start)
end = Node("end", parent=leader)

# Sanity check.
for pre, fill, node in RenderTree(start):
    print("%s%s" % (pre, node.name))

# Export to SVG.
UniqueDotExporter(start).to_picture("/tmp/workflow.svg")
