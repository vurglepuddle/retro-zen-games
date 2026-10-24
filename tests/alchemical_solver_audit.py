"""Bounded independent solver for Godot-exported five-layer boards.

Run after tests/export_alchemical_boards.gd (isolated APPDATA). Every reported solution
is replayed with the actual all-of-top-run pour rule. Budget exhaustion is
reported as unknown, never as an impossible board.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path


def solve(layers, seconds=0.6):
    start = tuple(tuple(c for c in vial if c) for vial in layers)
    capacity = 5
    deadline = time.monotonic() + seconds
    seen = {}
    nodes = 0

    def visit(board, path):
        nonlocal nodes
        nodes += 1
        if nodes % 128 == 0 and time.monotonic() >= deadline:
            raise TimeoutError
        if all(not v or len(v) == capacity and len(set(v)) == 1 for v in board):
            return path
        key = tuple(sorted(board))
        if seen.get(key, 10000) <= len(path):
            return None
        seen[key] = len(path)
        if len(path) >= 240:
            raise TimeoutError
        options = []
        used_sources = set()
        for i, src in enumerate(board):
            if not src or src in used_sources:
                continue
            used_sources.add(src)
            if len(src) == capacity and len(set(src)) == 1:
                continue
            run = 1
            while run < len(src) and src[-1-run] == src[-1]:
                run += 1
            used_destinations = set()
            for j, dst in enumerate(board):
                if i == j or len(dst) == capacity or dst in used_destinations:
                    continue
                if dst and dst[-1] != src[-1]:
                    continue
                used_destinations.add(dst)
                if not dst and run == len(src):
                    continue  # moving a pure bottle to an empty one only renames it
                amount = min(run, capacity-len(dst))
                priority = (0 if dst else 3) + (0 if len(dst)+amount == capacity else 1)
                options.append((priority, i, j, amount))
        for _, i, j, amount in sorted(options):
            next_board = list(board)
            next_board[i] = board[i][:-amount]
            next_board[j] = board[j] + (board[i][-1],) * amount
            result = visit(tuple(next_board), path+[(i,j)])
            if result is not None:
                return result
        return None

    try:
        path = visit(start, [])
    except TimeoutError:
        return {"result": "unknown", "nodes": nodes}
    if path is None:
        return {"result": "unsolvable", "nodes": nodes}
    # Independent forward replay catches pruning, capacity and partial-pour mistakes.
    board = [list(v) for v in start]
    for i, j in path:
        src, dst = board[i], board[j]
        assert src and len(dst) < capacity and (not dst or dst[-1] == src[-1])
        color = src[-1]
        run = 1
        while run < len(src) and src[-1-run] == color:
            run += 1
        amount = min(run, capacity-len(dst))
        del src[-amount:]
        dst.extend([color]*amount)
    assert all(not v or len(v) == capacity and len(set(v)) == 1 for v in board)
    return {"result": "solved", "nodes": nodes, "moves": len(path), "path": path}


if __name__ == "__main__":
    path = Path(sys.argv[1] if len(sys.argv) > 1 else ".godot/alchemy_boards.json")
    results = []
    for case in json.loads(path.read_text()):
        answer = solve(case["layers"])
        if answer["result"] == "unknown":
            answer = solve(case["layers"], seconds=4.0)
        result = {"seed": case["seed"], "mode": case["mode"], **answer}
        results.append(result)
        print({key: value for key, value in result.items() if key != "path"}, flush=True)
    counts = {key: sum(r["result"] == key for r in results) for key in ["solved", "unsolvable", "unknown"]}
    Path(".godot/alchemy_solver_results.json").write_text(json.dumps(results, indent=2))
    print("ALCHEMY SOLVER:", counts)
    if counts["unsolvable"]:
        raise SystemExit(1)
