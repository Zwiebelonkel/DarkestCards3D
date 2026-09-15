"""Rebuild the original textured hospital shell with a real door opening.

Run with Python 3 from any directory. Only the +X wall is rebuilt; the other
walls, floor, ceiling, material, UV layout and embedded texture are preserved.
The dimensions below are in Main's world space, before mirroring the second room.
"""

import json
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/environments/props/hospital/hospitalRoom.glb"
OUTPUT = ROOT / "scenes/rooms/HospitalRoomShell.glb"
ROOM_SCALE = (0.695, 0.695, 0.925)
ROOM_ORIGIN = (0.179363, -2.21619, 0.438384)
DOOR_CENTER_Z = 4.5
DOOR_WIDTH = 3.026
DOOR_HEIGHT = 5.763


def read_glb(path):
    source = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", source)
    assert magic == b"glTF" and version == 2 and length == len(source)
    json_size, json_kind = struct.unpack_from("<II", source, 12)
    assert json_kind == 0x4E4F534A
    document = json.loads(source[20:20 + json_size])
    binary_size, binary_kind = struct.unpack_from("<II", source, 20 + json_size)
    assert binary_kind == 0x004E4942
    return document, source[28 + json_size:28 + json_size + binary_size]


def read_accessor(document, binary, index, components, kind="f"):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    fmt = "<" + kind * components
    stride = view.get("byteStride", struct.calcsize(fmt))
    return [struct.unpack_from(fmt, binary, offset + i * stride)
            for i in range(accessor["count"])]


def main():
    document, binary = read_glb(SOURCE)
    primitive = document["meshes"][0]["primitives"][0]
    assert primitive["attributes"] == {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}
    assert primitive["indices"] == 3
    positions = read_accessor(document, binary, 0, 3)
    normals = read_accessor(document, binary, 1, 3)
    uvs = read_accessor(document, binary, 2, 2)
    old_indices = [item[0] for item in read_accessor(document, binary, 3, 1, "H")]
    node = document["nodes"][0]
    scale = node["scale"]
    translation = node["translation"]
    floor_y = min(position[1] for position in positions)
    ceiling_y = max(position[1] for position in positions)
    floor_world = ROOM_ORIGIN[1] + ROOM_SCALE[1] * (translation[1] + scale[1] * floor_y)

    def local_z(world_z):
        return ((world_z - ROOM_ORIGIN[2]) / ROOM_SCALE[2] - translation[2]) / scale[2]

    opening_z0 = local_z(DOOR_CENTER_Z - DOOR_WIDTH * 0.5)
    opening_z1 = local_z(DOOR_CENTER_Z + DOOR_WIDTH * 0.5)
    opening_top = floor_y + DOOR_HEIGHT / (ROOM_SCALE[1] * scale[1])
    assert -1.0 < opening_z0 < opening_z1 < 1.0
    assert floor_y < opening_top < ceiling_y

    # Keep the original non-door surfaces bit-for-bit in the vertex arrays.
    indices = []
    removed = []
    for start in range(0, len(old_indices), 3):
        triangle = old_indices[start:start + 3]
        if all(abs(positions[index][0] - 1.0) < 1e-6 for index in triangle):
            removed.append(triangle)
        else:
            indices.extend(triangle)
    assert removed, "Source room no longer contains the expected +X wall"

    def original_uv(y, z):
        for index in {index for triangle in removed for index in triangle}:
            if abs(positions[index][1] - y) < 1e-6 and abs(positions[index][2] - z) < 1e-6:
                return uvs[index]
        raise AssertionError("Original wall corner is missing")

    uv_floor_near = original_uv(floor_y, -1.0)
    uv_floor_far = original_uv(floor_y, 1.0)
    uv_top_near = original_uv(ceiling_y, -1.0)
    first_new_index = len(indices)

    def panel(y0, y1, z0, z1):
        start = len(positions)
        for y, z in ((y0, z0), (y1, z0), (y1, z1), (y0, z1)):
            positions.append((1.0, y, z))
            normals.append((1.0, 0.0, 0.0))
            fy = (y - floor_y) / (ceiling_y - floor_y)
            fz = (z + 1.0) * 0.5
            uvs.append(tuple(uv_floor_near[axis]
                             + fy * (uv_top_near[axis] - uv_floor_near[axis])
                             + fz * (uv_floor_far[axis] - uv_floor_near[axis])
                             for axis in range(2)))
        indices.extend(start + index for index in (0, 1, 2, 0, 2, 3))

    panel(floor_y, ceiling_y, -1.0, opening_z0)
    panel(floor_y, ceiling_y, opening_z1, 1.0)
    panel(opening_top, ceiling_y, opening_z0, opening_z1)

    # The portal rectangle must remain empty. The frame hides its boundary.
    for start in range(first_new_index, len(indices), 3):
        triangle = [positions[index] for index in indices[start:start + 3]]
        assert (max(v[2] for v in triangle) <= opening_z0
                or min(v[2] for v in triangle) >= opening_z1
                or min(v[1] for v in triangle) >= opening_top)

    new_binary = bytearray()
    for accessor_index, rows, fmt in (
            (0, positions, "<3f"), (1, normals, "<3f"),
            (2, uvs, "<2f"), (3, [(index,) for index in indices], "<H")):
        while len(new_binary) % 4:
            new_binary.append(0)
        accessor = document["accessors"][accessor_index]
        accessor["count"] = len(rows)
        accessor.pop("byteOffset", None)
        view = document["bufferViews"][accessor["bufferView"]]
        view["byteOffset"] = len(new_binary)
        view["byteLength"] = len(rows) * struct.calcsize(fmt)
        view.pop("byteStride", None)
        for row in rows:
            new_binary.extend(struct.pack(fmt, *row))
    document["accessors"][0]["min"] = [min(v[axis] for v in positions) for axis in range(3)]
    document["accessors"][0]["max"] = [max(v[axis] for v in positions) for axis in range(3)]
    for view in document["bufferViews"][4:]:
        payload = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
        while len(new_binary) % 4:
            new_binary.append(0)
        view["byteOffset"] = len(new_binary)
        new_binary.extend(payload)
    document["buffers"][0]["byteLength"] = len(new_binary)
    document["meshes"][0]["name"] = "HospitalWallsWithDoorway"
    document["nodes"][0]["name"] = "HospitalWalls"
    document["asset"]["extras"] = {"generator": "scripts/rooms/build_hospital_shell.py"}
    while len(new_binary) % 4:
        new_binary.append(0)
    encoded_json = json.dumps(document, separators=(",", ":")).encode()
    encoded_json += b" " * (-len(encoded_json) % 4)
    output = (struct.pack("<4sII", b"glTF", 2, 28 + len(encoded_json) + len(new_binary))
              + struct.pack("<II", len(encoded_json), 0x4E4F534A) + encoded_json
              + struct.pack("<II", len(new_binary), 0x004E4942) + new_binary)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(output)
    wall_world = ROOM_ORIGIN[0] + ROOM_SCALE[0] * (translation[0] + scale[0])
    print(f"Hospital shell: {len(removed)} wall triangles replaced by 6; UVs and texture preserved.")
    print(f"Door floor center: ({wall_world:.9f}, {floor_world:.9f}, {DOOR_CENTER_Z})")
    print(f"Door aperture: {DOOR_WIDTH} x {DOOR_HEIGHT}; top y={floor_world + DOOR_HEIGHT:.9f}")
    print(f"EmptyRoom root: ({2.0 * wall_world + 2.0 - ROOM_ORIGIN[0]:.9f}, 0, {2.0 * DOOR_CENTER_Z - ROOM_ORIGIN[2]:.9f})")


if __name__ == "__main__":
    main()
