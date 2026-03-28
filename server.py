"""
server.py
--------------------------------
Flask server that exposes path finding API for SkateMo iOS app.

Run with: python server.py
API will be available at http://localhost:5001/route
"""

from flask import Flask, request, jsonify
import networkx as nx
import pandas as pd
import math

app = Flask(__name__)

# Global graph and node names (loaded once at startup)
G = None
node_names = {}
nodes_list = []

def calculate_bearing(point1, point2):
    """Calculate bearing from point1 to point2. Points are (lat, lon) tuples."""
    lat1, lon1 = math.radians(point1[0]), math.radians(point1[1])
    lat2, lon2 = math.radians(point2[0]), math.radians(point2[1])

    dlon = lon2 - lon1
    x = math.sin(dlon) * math.cos(lat2)
    y = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon)

    bearing = math.atan2(x, y)
    return math.degrees(bearing)

def get_turn_direction(angle_diff):
    """Determine turn direction based on angle difference."""
    while angle_diff > 180:
        angle_diff -= 360
    while angle_diff < -180:
        angle_diff += 360

    if abs(angle_diff) < 30:
        return "Intersection"
    elif angle_diff > 0:
        return "Right"
    else:
        return "Left"

def generate_instructions(path):
    """Generate turn-by-turn instructions for each node in the path."""
    if len(path) == 0:
        return []
    if len(path) == 1:
        return ["Start"]

    instructions = []
    for i in range(len(path)):
        if i == 0:
            instructions.append("Start")
        elif i == len(path) - 1:
            instructions.append("Destination")
        else:
            incoming_bearing = calculate_bearing(path[i-1], path[i])
            outgoing_bearing = calculate_bearing(path[i], path[i+1])
            angle_diff = outgoing_bearing - incoming_bearing
            instructions.append(get_turn_direction(angle_diff))

    return instructions

def haversine_distance(point1, point2):
    """Calculate distance between two (lat, lon) points in meters."""
    R = 6371000  # Earth radius in meters
    lat1, lon1 = math.radians(point1[0]), math.radians(point1[1])
    lat2, lon2 = math.radians(point2[0]), math.radians(point2[1])

    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

    return R * c

def find_nearest_node(lat, lon):
    """Find the nearest graph node to the given coordinates."""
    target = (lat, lon)
    nearest = None
    min_dist = float('inf')

    for node in nodes_list:
        dist = haversine_distance(target, node)
        if dist < min_dist:
            min_dist = dist
            nearest = node

    return nearest, min_dist

def load_graph():
    """Load the campus graph from CSV."""
    global G, node_names, nodes_list

    CSV_PATH = "data/usc_campus_internal_edges.csv"
    df = pd.read_csv(CSV_PATH)

    G = nx.Graph()
    for _, row in df.iterrows():
        u = (row["Intersection 1 Lat"], row["Intersection 1 Lon"])
        v = (row["Intersection 2 Lat"], row["Intersection 2 Lon"])
        distance = row["Distance (ft)"]
        G.add_edge(u, v, weight=distance, name=row.get("Road Name", "Unnamed"))

    # Build node-to-intersection-name mapping
    for node in G.nodes():
        roads = set()
        for neighbor in G.neighbors(node):
            road_name = G[node][neighbor].get("name", "Unnamed")
            if road_name and road_name != "Unnamed":
                roads.add(road_name)
        if len(roads) >= 2:
            node_names[node] = " & ".join(sorted(roads))
        elif len(roads) == 1:
            node_names[node] = list(roads)[0]
        else:
            node_names[node] = f"({node[0]:.4f}, {node[1]:.4f})"

    nodes_list = list(G.nodes())
    print(f"Graph loaded: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges")

@app.route('/route', methods=['GET'])
def get_route():
    """
    Get route between two points.

    Query params:
        start_lat, start_lon: Starting coordinates
        end_lat, end_lon: Destination coordinates

    Returns:
        JSON with waypoints array containing name, lat, lon, instruction
    """
    try:
        start_lat = float(request.args.get('start_lat'))
        start_lon = float(request.args.get('start_lon'))
        end_lat = float(request.args.get('end_lat'))
        end_lon = float(request.args.get('end_lon'))
    except (TypeError, ValueError):
        return jsonify({"error": "Invalid coordinates"}), 400

    # Find nearest nodes
    start_node, start_dist = find_nearest_node(start_lat, start_lon)
    end_node, end_dist = find_nearest_node(end_lat, end_lon)

    if start_node is None or end_node is None:
        return jsonify({"error": "Could not find nearby nodes"}), 404

    # Check if nodes are too far (> 200m from any path)
    if start_dist > 200:
        return jsonify({"error": f"Start point is {start_dist:.0f}m from nearest path"}), 404
    if end_dist > 200:
        return jsonify({"error": f"Destination is {end_dist:.0f}m from nearest path"}), 404

    try:
        # Compute shortest path
        path = nx.shortest_path(G, source=start_node, target=end_node, weight="weight")
        path_length = nx.shortest_path_length(G, source=start_node, target=end_node, weight="weight")
    except nx.NetworkXNoPath:
        return jsonify({"error": "No path found between points"}), 404

    # Generate instructions
    instructions = generate_instructions(path)

    # Build waypoints response
    waypoints = []
    for i, node in enumerate(path):
        waypoints.append({
            "name": node_names.get(node, "Unnamed"),
            "latitude": node[0],
            "longitude": node[1],
            "instruction": instructions[i]
        })

    return jsonify({
        "waypoints": waypoints,
        "total_distance_ft": round(path_length, 1),
        "start_distance_m": round(start_dist, 1),
        "end_distance_m": round(end_dist, 1)
    })

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({
        "status": "ok",
        "nodes": G.number_of_nodes() if G else 0,
        "edges": G.number_of_edges() if G else 0
    })

if __name__ == '__main__':
    load_graph()
    print("Starting SkateMo Route Server on http://localhost:5001")
    app.run(host='0.0.0.0', port=5001, debug=True)
