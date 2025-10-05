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