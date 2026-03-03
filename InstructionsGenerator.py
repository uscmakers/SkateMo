"""
InstructionsGenerator.py
--------------------------------
Generates instruction arrays from a shortest path.
"""

import math

def calculate_bearing(point1, point2):
    """
    Calculate the bearing (angle) from point1 to point2.
    Points are (lat, lon) tuples.
    Returns angle in degrees.
    """
    lat1, lon1 = math.radians(point1[0]), math.radians(point1[1])
    lat2, lon2 = math.radians(point2[0]), math.radians(point2[1])

    dlon = lon2 - lon1
    x = math.sin(dlon) * math.cos(lat2)
    y = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon)

    bearing = math.atan2(x, y)
    return math.degrees(bearing)

def get_turn_direction(angle_diff):
    """
    Determine turn direction based on angle difference.
    Positive = right turn, Negative = left turn.
    """
    # Normalize to -180 to 180
    while angle_diff > 180:
        angle_diff -= 360
    while angle_diff < -180:
        angle_diff += 360

    # Threshold for straight (within ~30 degrees)
    if abs(angle_diff) < 30:
        return "Intersection"
    elif angle_diff > 0:
        return "Right"
    else:
        return "Left"

def generate_node_array(path, node_names):
    """
    Takes a shortest path (list of nodes) and prints the nodes array with names.

    Args:
        path: List of nodes (each node is a (lat, lon) tuple)
        node_names: Dictionary mapping nodes to their intersection names

    Returns:
        The nodes array with names
    """
    nodes_array = [(node_names.get(node, "Unnamed"), node) for node in path]

    print(f"\n--- Nodes Array (length: {len(nodes_array)}) ---")
    print(nodes_array)

    return nodes_array

def generate_instructions_array(path):
    """
    Generate turn-by-turn instructions for each node in the path.

    Args:
        path: List of nodes (each node is a (lat, lon) tuple)

    Returns:
        List of instructions: Start, Left, Right, Intersection, Destination
    """
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
            # Calculate turn direction
            incoming_bearing = calculate_bearing(path[i-1], path[i])
            outgoing_bearing = calculate_bearing(path[i], path[i+1])
            angle_diff = outgoing_bearing - incoming_bearing

            instruction = get_turn_direction(angle_diff)
            instructions.append(instruction)

    print(f"\n--- Instructions Array (length: {len(instructions)}) ---")
    print(instructions)

    return instructions
