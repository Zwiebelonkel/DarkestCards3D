"""Bake the connected room door openings into the original textured hub shell.

Run from any directory: py -3 scripts/tools/build_connected_hospital_shell.py
The source GLB and the slot room's shell stay unchanged. UVs/materials/images are
preserved; only triangles on the affected walls are split around openings.
"""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scenes/rooms/HospitalRoomShell.glb"
TARGET = ROOT / "scenes/rooms/ConnectedHospitalRoomShell.glb"


def clip(poly, axis, bound, greater):
    result = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        av, bv = a["POSITION"][axis], b["POSITION"][axis]
        a_in = av >= bound if greater else av <= bound
        b_in = bv >= bound if greater else bv <= bound
        if a_in:
            result.append(a)
        if a_in != b_in:
            weight = (bound - av) / (bv - av)
            result.append({key: [x + (y - x) * weight for x, y in zip(a[key], b[key])]
                           for key in a})
    return result


def subtract_rect(poly, bounds):
    remaining, outside = poly, []
    for axis, low, high in bounds:
        for bound, greater in [(low, True), (high, False)]:
            piece = clip(remaining, axis, bound, not greater)
            if len(piece) >= 3:
                outside.append(piece)
            remaining = clip(remaining, axis, bound, greater)
            if not remaining:
                return outside
    return outside


def build():
    data = SOURCE.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + length])
    bin_start = 20 + length + 8
    binary = bytearray(data[bin_start:])
    primitive = doc["meshes"][0]["primitives"][0]
    node = next(node for node in doc["nodes"] if node.get("mesh") == 0)
    sizes = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
    formats = {5123: "H", 5125: "I", 5126: "f"}

    def read(index):
        accessor = doc["accessors"][index]
        view = doc["bufferViews"][accessor["bufferView"]]
        fmt = "<" + formats[accessor["componentType"]] * sizes[accessor["type"]]
        stride = view.get("byteStride", struct.calcsize(fmt))
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return [list(struct.unpack_from(fmt, binary, offset + i * stride))
                for i in range(accessor["count"])]

    attrs = {key: read(index) for key, index in primitive["attributes"].items()}
    indices = [entry[0] for entry in read(primitive["indices"])]
    hub_scale, hub_origin = [0.695, 0.695, 0.925], [0.179363, -2.21619, 0.438384]

    def local(axis, world):
        return ((world - hub_origin[axis]) / hub_scale[axis]
                - node.get("translation", [0, 0, 0])[axis]) / node["scale"][axis]

    half_width = 1.6574795 * 1.825 / 2
    top = -2.22292 + 3.1579228 * 1.825
    holes = [
        (0, 1, [(2, local(2, -4.1 - half_width), local(2, -4.1 + half_width)),
             (1, -1.001, local(1, top))]),
        (0, -1, [(2, local(2, -4.1 - half_width), local(2, -4.1 + half_width)),
             (1, -1.001, local(1, top))]),
        (2, 1, [(0, local(0, -4.3 - half_width), local(0, -4.3 + half_width)),
             (1, -1.001, local(1, top))]),
    ]
    vertices = []
    for start in range(0, len(indices), 3):
        triangle = [{key: value[index] for key, value in attrs.items()}
                    for index in indices[start:start + 3]]
        polygons = [triangle]
        for wall_axis, wall_side, bounds in holes:
            if all(abs(v["POSITION"][wall_axis] - wall_side) < 0.0001 for v in triangle):
                polygons = [piece for poly in polygons for piece in subtract_rect(poly, bounds)]
        for poly in polygons:
            for index in range(1, len(poly) - 1):
                vertices.extend([poly[0], poly[index], poly[index + 1]])

    def append(values, kind, component_type=5126):
        while len(binary) % 4:
            binary.append(0)
        fmt = "<" + formats[component_type] * sizes[kind]
        payload = b"".join(struct.pack(fmt, *value) for value in values)
        view_index = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(payload)})
        binary.extend(payload)
        accessor = {"bufferView": view_index, "componentType": component_type,
                    "count": len(values), "type": kind}
        if kind == "VEC3":
            accessor.update(min=[min(v[i] for v in values) for i in range(3)],
                            max=[max(v[i] for v in values) for i in range(3)])
        doc["accessors"].append(accessor)
        return len(doc["accessors"]) - 1

    for key in list(primitive["attributes"]):
        values = [v[key] for v in vertices]
        if key == "NORMAL":
            values = [[x / max(math.sqrt(sum(c * c for c in v)), 1e-10) for x in v] for v in values]
        primitive["attributes"][key] = append(values, "VEC" + str(len(values[0])))
    primitive["indices"] = append([[i] for i in range(len(vertices))], "SCALAR", 5125)
    doc["buffers"][0]["byteLength"] = len(binary)
    json_bytes = json.dumps(doc, separators=(",", ":")).encode()
    json_bytes += b" " * (-len(json_bytes) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    TARGET.write_bytes(struct.pack("<III", 0x46546C67, 2, total)
                       + struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
                       + struct.pack("<II", len(binary), 0x004E4942) + binary)
    print(f"Baked {len(vertices) // 3} triangles into {TARGET.name}")


if __name__ == "__main__":
    build()
