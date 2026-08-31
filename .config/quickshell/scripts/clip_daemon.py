#!/usr/bin/env python3

import json
import subprocess
import time


MAX_VISIBLE_ITEMS = 25
POLL_INTERVAL = 0.75


def get_history():
    try:
        result = subprocess.run(
            ["cliphist", "list"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            return []

        items = []

        for line in result.stdout.splitlines()[:MAX_VISIBLE_ITEMS]:
            if not line.strip():
                continue

            try:
                clip_id, content = line.split("\t", 1)
            except ValueError:
                continue

            items.append({
                "id": clip_id,
                "content": content,
            })

        return items

    except Exception as exc:
        print(f"ERROR|{exc}", flush=True)
        return []


def emit(items):
    print(
        "CLIP|" + json.dumps(
            items,
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        flush=True,
    )


def main():
    previous = None

    while True:
        items = get_history()

        if items != previous:
            emit(items)
            previous = items

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()