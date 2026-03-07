# SkateMo System Architecture Overview

Document Type: Target End-State Architecture (not current implementation)  
Last verified against repository: March 7, 2026  
Implementation status: Partial

This document describes how SkateMo is intended to function when complete. It is the architectural target state, not a claim that all modules are currently implemented in this repository.

Detailed implementation logic belongs in source modules as they are built.

---

# System Overview

SkateMo is an autonomous skateboard capable of transporting a rider from point A to point B.

The complete system combines:

- Computer vision for obstacle detection
- Map-based route planning
- Intersection-based navigation
- Heading-based turn control
- Safety-first stopping behavior

Prototype behavior is intentionally conservative: when obstacles are detected, the board stops rather than attempting avoidance.

The system is split into two major components:

1. iPhone autonomy app (high-level intelligence)
2. Skateboard hardware platform (motion execution)

---

# High-Level Architecture

The system uses a two-layer architecture.

## Layer 1: High-Level Autonomy (iPhone App)

The iPhone is the primary compute and sensing platform.

Responsibilities:

- Camera input
- Computer vision processing (target: MediaPipe-based pipeline)
- Obstacle detection
- GPS/location services
- Map access
- Route generation
- Path interpretation
- Intersection detection
- Turn decision generation

The phone determines what the skateboard should do.

Example decisions:

- continue forward
- turn left at next intersection
- turn right
- stop due to obstacle

## Layer 2: Motion Execution (Skateboard Platform)

The skateboard hardware executes commands produced by the phone.

Responsibilities:

- propulsion
- braking/power cutoff
- turning actuation
- heading sensing
- executing motion commands

The board determines how to physically perform the requested motion.

---

# Navigation Model

Navigation is map-based.

The iPhone generates a route from current location to destination using map data.

The route is interpreted as a sequence of road segments and intersection actions:

segment -> intersection -> segment -> intersection -> destination

Each intersection contains a directional instruction:

- LEFT
- RIGHT
- STRAIGHT

---

# Intersection Handling

When the skateboard enters a predefined radius around an intersection:

1. Check the planned route
2. Retrieve the next directional instruction
3. Execute the maneuver

Possible actions:

- Continue straight
- Turn left
- Turn right

---

# Turn Control

Turning uses heading feedback from the skateboard.

Process:

1. Initiate a turn (left or right)
2. Begin rotating
3. Continuously read heading
4. Stop turn when orientation matches target road heading

Turns should terminate based on orientation, not fixed time delays.

---

# Obstacle Handling (Prototype Behavior)

Obstacle detection runs on the iPhone camera pipeline (target architecture).

If an obstacle is detected ahead:

1. Stop motion commands
2. Cut motor power
3. Halt the skateboard

Current prototype philosophy does not include obstacle avoidance or swerving.

Future capabilities may include:

- obstacle bypass
- local path replanning
- pedestrian-aware navigation

---

# System Control Flow

Simplified control loop:

1. Capture camera frame
2. Run computer vision
3. Detect obstacles
4. If obstacle detected -> stop
5. Else check location against next intersection
6. If intersection reached:
   - read route instruction
   - execute turn if needed
7. Continue forward motion

---

# Design Philosophy

The architecture prioritizes:

- simplicity
- safety
- clear control logic
- testable autonomy behaviors

More advanced behaviors (dynamic obstacle avoidance, local planning, smoother path following) are layered on only after core reliability is proven.

---

# Current Repository Reality (March 7, 2026)

This section exists to prevent ambiguity between target design and current code state.

- Implemented now: map extraction, graph routing, instruction generation, YOLO-based CV prototypes
- Not fully implemented now: complete iPhone autonomy app, integrated phone-to-board control loop, heading-closed turn controller, full safety supervisor
- Therefore: this document should be treated as the end-state system contract, not a statement of completed implementation

---

# Notes for Developers and AI Agents

When modifying the system, preserve these architectural boundaries:

- High-level decisions originate from the iPhone autonomy layer
- Skateboard platform focuses on reliable execution of motion commands
- Heading feedback is the primary turn-termination mechanism
- Obstacle detection has highest priority and can force a stop

As code evolves, update module-level docs and keep this file aligned with target architecture and explicit implementation status.
