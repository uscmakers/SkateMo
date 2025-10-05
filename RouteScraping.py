# pip install osmnx pandas networkx matplotlib

import osmnx as ox
import networkx as nx
import pandas as pd
import os

PLACE = "University of Southern California, Los Angeles, California, USA"

# ---------- 1) Create output folder ----------
BASE_DIR = os.path.dirname(__file__)
DATA_DIR = os.path.join(BASE_DIR, "data")
os.makedirs(DATA_DIR, exist_ok=True)
OUT_CSV = os.path.join(DATA_DIR, "usc_campus_internal_edges.csv")

# ---------- 2) Get USC polygon ----------
campus_gdf = ox.geocode_to_gdf(PLACE)
polygon = campus_gdf.geometry.iloc[0]

# ---------- 3) Build graph inside polygon ----------
G = ox.graph_from_polygon(polygon, network_type="walk", simplify=True)

# ---------- 4) Filter to keep campus-like roads ----------
KEEP = {"footway", "path", "pedestrian", "living_street", "service", "residential", "unclassified"}
DROP = {"primary", "secondary", "tertiary", "motorway", "trunk"}

edges_to_remove = []
for u, v, k, data in G.edges(keys=True, data=True):
    hw = data.get("highway")
    hw_list = hw if isinstance(hw, list) else [hw]
    if any(h in DROP for h in hw_list) or not any(h in KEEP for h in hw_list):
        edges_to_remove.append((u, v, k))
G.remove_edges_from(edges_to_remove)

# ---------- 5) Remove isolates / keep largest component ----------
UG = G.to_undirected()
isolates = list(nx.isolates(UG))
G.remove_nodes_from(isolates)
if not nx.is_empty(G):
    largest_cc_nodes = max(nx.connected_components(G.to_undirected()), key=len)
    G = G.subgraph(largest_cc_nodes).copy()

# ---------- 6) Export edge list to CSV ----------
edges = []
for u, v, data in G.edges(data=True):
    name = data.get("name", "Unnamed")
    length_m = float(data.get("length", 0.0))
    hw = data.get("highway")
    hw_str = ", ".join(hw) if isinstance(hw, list) else hw
    edges.append((
        G.nodes[u]["y"], G.nodes[u]["x"],
        G.nodes[v]["y"], G.nodes[v]["x"],
        name, hw_str, round(length_m * 3.28084, 1)
    ))

df = pd.DataFrame(edges, columns=[
    "Intersection 1 Lat", "Intersection 1 Lon",
    "Intersection 2 Lat", "Intersection 2 Lon",
    "Road Name", "Highway Type(s)", "Distance (ft)"
])

print(f"\n✅ USC graph has {len(df)} edges. Saving to CSV…")
print("Path:", OUT_CSV)
df.to_csv(OUT_CSV, index=False)
print(f"✅ Saved {len(df)} edges to {OUT_CSV}")