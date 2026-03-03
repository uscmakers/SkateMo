"""
ShortestPathVisualizer.py
--------------------------------
Reads the campus edges CSV, builds a NetworkX graph,
selects two random intersections, computes the shortest path
using Dijkstra's algorithm, and highlights it in green.
"""

# Requirements:
# pip install osmnx pandas networkx matplotlib

import osmnx as ox
import networkx as nx
import pandas as pd
import random
import matplotlib.pyplot as plt
from InstructionsGenerator import generate_node_array, generate_instructions_array

# --- 1) Load the CSV of campus roads ---
CSV_PATH = "usc_campus_internal_edges.csv"
df = pd.read_csv(CSV_PATH)

# --- 2) Build graph ---
G = nx.Graph()
for _, row in df.iterrows():
    u = (row["Intersection 1 Lat"], row["Intersection 1 Lon"])
    v = (row["Intersection 2 Lat"], row["Intersection 2 Lon"])
    distance = row["Distance (ft)"]
    G.add_edge(u, v, weight=distance, name=row.get("Road Name", "Unnamed"))

print(f"✅ Graph built with {G.number_of_nodes()} nodes and {G.number_of_edges()} edges")

# --- Build node-to-intersection-name mapping ---
node_names = {}
for node in G.nodes():
    roads = set()
    for neighbor in G.neighbors(node):
        road_name = G[node][neighbor].get("name", "Unnamed")
        if road_name != "Unnamed":
            roads.add(road_name)
    if len(roads) >= 2:
        node_names[node] = " & ".join(sorted(roads))
    elif len(roads) == 1:
        node_names[node] = list(roads)[0]
    else:
        node_names[node] = f"({node[0]:.4f}, {node[1]:.4f})"

# --- 3) Pick random start and end nodes ---
nodes = list(G.nodes())
start = random.choice(nodes)
end = random.choice(nodes)
while end == start:
    end = random.choice(nodes)

print(f"Random Start Node: {start}")
print(f"Random End Node:   {end}")

# --- 4) Dijkstra shortest path ---
path = nx.shortest_path(G, source=start, target=end, weight="weight")
path_length = nx.shortest_path_length(G, source=start, target=end, weight="weight")
print(f"Shortest Path Distance: {path_length:.1f} ft")

# --- Generate node array and instructions array ---
nodes_array = generate_node_array(path, node_names)
instructions_array = generate_instructions_array(path)

# --- 5) Plot graph + highlight shortest path ---
pos = {node: (node[1], node[0]) for node in G.nodes()}  # (lon, lat)

# Draw base network
nx.draw(G, pos, node_size=10, node_color="red", edge_color="gray", linewidths=0.3)

# Highlight the shortest path in green
path_edges = list(zip(path[:-1], path[1:]))
nx.draw_networkx_edges(G, pos, edgelist=path_edges, width=3, edge_color="limegreen")

plt.title("USC Campus Shortest Path (Dijkstra)")
plt.xlabel("Longitude")
plt.ylabel("Latitude")
plt.tight_layout()
plt.show()