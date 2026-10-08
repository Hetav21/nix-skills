"""agent-mcp-merge FILE KEY SERVERS_JSON [STATE]

Writes the MCP servers in SERVERS_JSON under KEY of FILE (JSON, or TOML by
extension), keeping everything else in FILE, including TOML comments. A
symlinked FILE is updated through the link.

Without STATE, KEY is replaced entirely. With STATE, only the servers recorded
there by the previous run are replaced or removed, so servers added by hand
survive; STATE is then updated to the servers just written.
"""
import json
import os
import sys
import tempfile

import tomlkit


def load(path, is_toml):
    try:
        with open(path) as f:
            text = f.read()
    except FileNotFoundError:
        return tomlkit.document() if is_toml else {}
    try:
        return tomlkit.parse(text) if is_toml else json.loads(text)
    except ValueError as e:
        sys.exit(f"agent-mcp-merge: cannot parse {path}: {e}")


def write_atomic(path, text):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    if os.path.exists(path):
        mode = os.stat(path).st_mode & 0o7777
    else:
        umask = os.umask(0)
        os.umask(umask)
        mode = 0o666 & ~umask
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=os.path.basename(path))
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def main(path, key, servers_path, state_path=None):
    path = os.path.realpath(path)
    is_toml = path.endswith(".toml")
    with open(servers_path) as f:
        servers = json.load(f)

    doc = load(path, is_toml)
    table = doc.get(key, {})
    if state_path is None:
        previous = list(table)
    elif os.path.exists(state_path):
        with open(state_path) as f:
            previous = json.load(f)
    else:
        previous = []

    for name in previous:
        table.pop(name, None)
    table.update(servers)
    if key not in doc:
        doc[key] = table

    if is_toml:
        write_atomic(path, tomlkit.dumps(doc))
    else:
        write_atomic(path, json.dumps(doc, indent=2) + "\n")
    if state_path is not None:
        write_atomic(state_path, json.dumps(sorted(servers)) + "\n")


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    try:
        main(*sys.argv[1:])
    except OSError as e:
        sys.exit(f"agent-mcp-merge: {e}")
