#!/usr/bin/env python3
"""Post-process a kicad-cli GLB export into a real-time-renderer-friendly asset.

``kicad-cli pcb export glb`` produces a physically-minded GLB via OpenCASCADE.
That is a good fit for CAD viewers and a poor one for engines like PlayCanvas,
three.js or Babylon. This script rewrites the glTF JSON chunk to fix the
differences. The binary chunk is never touched, so geometry is preserved
bit-for-bit and the pass is lossless.

What it fixes, and why:

1. Component materials converted from VRML carry a ``baseColorFactor`` and
   nothing else. glTF defaults the absent ``metallicFactor`` and
   ``roughnessFactor`` to 1.0, so every part renders as a fully metallic,
   fully rough surface -- dark and muddy under image-based lighting. We supply
   sensible PBR values instead.

2. The board body, soldermask and silkscreen are emitted as ``alphaMode:
   BLEND``. Engines depth-sort transparent meshes per object, so four stacked
   translucent layers z-fight and pop while orbiting. We make them opaque.
   With ``--mask-opacity`` below 1 the soldermask alone stays blended: one
   blended layer above opaque geometry sorts correctly, and copper under it
   then reads as tinted relief, the way tracks look on a real board.

3. Everything is ``doubleSided: true``, which disables backface culling and
   doubles fragment cost. Winding is verified consistent with the vertex
   normals in kicad-cli's output, so culling is safe to enable.

4. Nodes are named with OpenCASCADE label paths (``=>[0:1:1:4]``) and
   materials are ``mat_0``..``mat_n``, neither of which can be targeted from
   engine script. We name both after what they actually are.

5. The board is exported in metres offset from the origin, so it orbits around
   a pivot outside itself. We recentre it on its own bounding box.

Requires only the standard library.
"""

import argparse
import json
import re
import struct
import sys
from pathlib import Path

GLB_MAGIC = b"glTF"
CHUNK_JSON = b"JSON"
CHUNK_BIN = b"BIN\x00"

# kicad-cli names each board-layer mesh "<boardname>_<role>". Component meshes
# are named after their 3D model instead, and sit under a reference-designator
# node, so anything unmatched here is treated as a component.
ROLE_SUFFIXES = (
    ("_soldermask", "soldermask"),
    ("_silkscreen", "silkscreen"),
    ("_copper", "copper"),
    ("_pad", "pad"),
    ("_PCB", "board"),
)


def log(msg):
    print(f"  {msg}")


def notice(msg):
    print(f"::notice::{msg}")


def warn(msg):
    print(f"::warning::{msg}")


# --------------------------------------------------------------------------
# GLB container
# --------------------------------------------------------------------------


def read_glb(path):
    data = Path(path).read_bytes()
    if len(data) < 12:
        raise ValueError(f"{path}: too short to be a GLB")
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError(f"{path}: not a GLB (magic {magic!r})")
    if version != 2:
        raise ValueError(f"{path}: unsupported GLB version {version}")

    gltf = None
    binary = b""
    offset = 12
    while offset + 8 <= min(length, len(data)):
        clen, ctype = struct.unpack_from("<I4s", data, offset)
        offset += 8
        chunk = data[offset:offset + clen]
        if ctype == CHUNK_JSON:
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            binary = chunk
        offset += clen
    if gltf is None:
        raise ValueError(f"{path}: no JSON chunk")
    return gltf, binary


def write_glb(path, gltf, binary):
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)          # pad with spaces
    bin_bytes = binary + b"\x00" * (-len(binary) % 4)    # pad with zeroes

    total = 12 + 8 + len(json_bytes)
    if bin_bytes:
        total += 8 + len(bin_bytes)

    out = bytearray()
    out += struct.pack("<4sII", GLB_MAGIC, 2, total)
    out += struct.pack("<I4s", len(json_bytes), CHUNK_JSON) + json_bytes
    if bin_bytes:
        out += struct.pack("<I4s", len(bin_bytes), CHUNK_BIN) + bin_bytes
    Path(path).write_bytes(out)
    return total


# --------------------------------------------------------------------------
# Classification
# --------------------------------------------------------------------------


def mesh_role(name):
    for suffix, role in ROLE_SUFFIXES:
        if name.endswith(suffix):
            return role
    return "component"


# OpenCASCADE names nodes after the label path of the shape they came from,
# in either of two spellings: '=>[0:1:1:13]' and '=>0:1:1:14'.
OCCT_LABEL_RE = re.compile(r"^=>\[?[\d:]+\]?$")


def is_occt_label(name):
    return bool(name) and bool(OCCT_LABEL_RE.match(name))


def hex_of(base_color):
    """Six-digit uppercase hex for a glTF baseColorFactor."""
    return "".join(
        f"{int(round(min(1.0, max(0.0, c)) * 255)):02X}" for c in base_color[:3]
    )


def parse_color_list(raw):
    """Parse a comma-separated list of hex colours into normalised 6-digit hex.

    Accepts '#EDBE51', 'edbe51' and 3-digit shorthand like 'fff'.
    """
    out = set()
    bad = []
    for token in (raw or "").replace(";", ",").split(","):
        token = token.strip().lstrip("#").upper()
        if not token:
            continue
        if len(token) == 3 and all(c in "0123456789ABCDEF" for c in token):
            token = "".join(c * 2 for c in token)
        if len(token) == 6 and all(c in "0123456789ABCDEF" for c in token):
            out.add(token)
        else:
            bad.append(token)
    return out, bad


def unique_name(desired, taken):
    """Return `desired`, suffixed if needed, and record it in `taken`."""
    name = desired
    n = 2
    while name in taken:
        name = f"{desired}_{n}"
        n += 1
    taken.add(name)
    return name


def pretty_from_label(label, table):
    """Pretty name for a label, including the side/index-suffixed forms.

    The side suffixes are generated (``copper_front``, ``soldermask_0``,
    ``copper_2`` for an inner layer), so the tables cannot enumerate them.
    Returns None when nothing matches, leaving the caller to decide.
    """
    if label in table:
        return table[label]
    base, _, tail = label.rpartition("_")
    if base in table and (tail.isdigit() or tail in ("front", "back")):
        return f"{table[base]}_{tail.title()}"
    return None


def dominant_normal_axis(gltf, binary, mesh):
    """Return the sign of the dominant Y component of a mesh's normals.

    kicad-cli exports soldermask and silkscreen as flat single-sided faces, and
    emits front and back layers as two meshes with identical names. Their
    normals point along +Y and -Y respectively, which is how we tell them
    apart. Returns +1, -1, or 0 when indeterminate.
    """
    accessors = gltf.get("accessors", [])
    views = gltf.get("bufferViews", [])
    total = 0.0
    for prim in mesh.get("primitives", []):
        idx = prim.get("attributes", {}).get("NORMAL")
        if idx is None:
            continue
        acc = accessors[idx]
        if acc.get("componentType") != 5126 or acc.get("type") != "VEC3":
            continue
        view = views[acc["bufferView"]]
        if view.get("buffer", 0) != 0:
            continue
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride") or 12
        # Sampling is enough; these meshes are uniformly oriented.
        count = min(acc["count"], 256)
        for i in range(count):
            at = base + i * stride
            if at + 12 > len(binary):
                break
            total += struct.unpack_from("<3f", binary, at)[1]
    if total > 1e-6:
        return 1
    if total < -1e-6:
        return -1
    return 0


def build_node_index(gltf):
    """Map mesh index -> (node index, parent node index)."""
    nodes = gltf.get("nodes", [])
    parent_of = {}
    for i, node in enumerate(nodes):
        for child in node.get("children", []):
            parent_of[child] = i
    by_mesh = {}
    for i, node in enumerate(nodes):
        if "mesh" in node:
            by_mesh.setdefault(node["mesh"], (i, parent_of.get(i)))
    return by_mesh, parent_of


# --------------------------------------------------------------------------
# Bounding box
# --------------------------------------------------------------------------


def mesh_bounds(gltf, mesh):
    accessors = gltf.get("accessors", [])
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    found = False
    for prim in mesh.get("primitives", []):
        idx = prim.get("attributes", {}).get("POSITION")
        if idx is None:
            continue
        acc = accessors[idx]
        if "min" not in acc or "max" not in acc:
            continue
        found = True
        for axis in range(3):
            lo[axis] = min(lo[axis], acc["min"][axis])
            hi[axis] = max(hi[axis], acc["max"][axis])
    return (lo, hi) if found else None


# --------------------------------------------------------------------------
# Material policy
# --------------------------------------------------------------------------


def rgb_to_sat_val(rgb):
    r, g, b = rgb[:3]
    hi, lo = max(r, g, b), min(r, g, b)
    sat = 0.0 if hi <= 0 else (hi - lo) / hi
    return sat, hi


def looks_like_bare_metal(rgb, low=0.25, high=0.85, sat_max=0.15):
    """Guess whether a VRML-derived colour represents bare metal.

    Leads, shields and can bodies in KiCad's 3D libraries are mid-grey and
    nearly unsaturated. White or off-white plastic is also unsaturated but much
    brighter, so an upper bound on value keeps housings out.
    """
    sat, val = rgb_to_sat_val(rgb)
    return sat < sat_max and low < val < high


def set_pbr(material, metallic=None, roughness=None):
    pbr = material.setdefault("pbrMetallicRoughness", {})
    if metallic is not None:
        pbr["metallicFactor"] = round(metallic, 4)
    if roughness is not None:
        pbr["roughnessFactor"] = round(roughness, 4)


def make_opaque(material):
    """Force a material opaque, dropping the alpha channel and blend mode."""
    changed = material.pop("alphaMode", None) == "BLEND"
    material.pop("alphaCutoff", None)
    pbr = material.setdefault("pbrMetallicRoughness", {})
    base = pbr.get("baseColorFactor")
    if base is not None and len(base) == 4 and base[3] < 1.0:
        pbr["baseColorFactor"] = list(base[:3]) + [1.0]
        changed = True
    return changed


def make_translucent(material, opacity):
    """Keep a material blended at a fixed alpha."""
    material["alphaMode"] = "BLEND"
    material.pop("alphaCutoff", None)
    pbr = material.setdefault("pbrMetallicRoughness", {})
    base = list(pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0]))[:3]
    pbr["baseColorFactor"] = base + [round(opacity, 4)]


# --------------------------------------------------------------------------
# Main pass
# --------------------------------------------------------------------------


BOARD_ROLES = ("board", "soldermask", "silkscreen", "copper", "pad")


def process(gltf, binary, opts):
    meshes = gltf.get("meshes", [])
    nodes = gltf.get("nodes", [])
    materials = gltf.get("materials", [])
    stats = {
        "opaque": 0, "translucent": 0, "culled": 0, "pbr_fixed": 0, "metal": 0,
        "forced_metal": 0, "renamed_nodes": 0, "renamed_mats": 0,
    }

    metal_colours, bad_colours = parse_color_list(opts.metal_colors)
    if bad_colours:
        warn("Ignoring unparseable --metal-colors entries: " + ", ".join(bad_colours))
    matched_colours = set()
    taken_mats = set()

    if not meshes:
        warn("GLB contains no meshes; nothing to post-process.")
        return stats

    by_mesh, parent_of = build_node_index(gltf)

    # ---- classify meshes, disambiguating front/back flat-face layers -------
    roles = {}
    seen_sides = {}
    for mi, mesh in enumerate(meshes):
        role = mesh_role(mesh.get("name", ""))
        label = role
        if role in ("soldermask", "silkscreen"):
            sign = dominant_normal_axis(gltf, binary, mesh)
            if sign > 0:
                label = f"{role}_front"
            elif sign < 0:
                label = f"{role}_back"
            else:
                n = seen_sides.get(role, 0)
                seen_sides[role] = n + 1
                label = f"{role}_{n}"
        roles[mi] = (role, label)

    # Copper and pads are not flat single-sided faces, so the normal test
    # above cannot place them. Order them by height instead: geometry is
    # stable across exports, mesh order is not, and an unstable name silently
    # retargets any override written against it downstream -- the same failure
    # the colour-derived material names exist to avoid.
    for side_role in ("copper", "pad"):
        members = [mi for mi in sorted(roles) if roles[mi][0] == side_role]
        if len(members) < 2:
            continue
        heights = {}
        for mi in members:
            b = mesh_bounds(gltf, meshes[mi])
            heights[mi] = (b[0][1] + b[1][1]) / 2.0 if b else 0.0
        if len(set(heights.values())) == 1:
            continue  # no height information to separate them by
        ordered = sorted(members, key=lambda mi: (-heights[mi], mi))
        for n, mi in enumerate(ordered):
            if n == 0:
                label = f"{side_role}_front"
            elif n == len(ordered) - 1:
                label = f"{side_role}_back"
            else:
                label = f"{side_role}_{n}"
            roles[mi] = (side_role, label)

    # mesh_role() falls back to "component", so a renamed kicad-cli suffix
    # would quietly give every board layer component treatment.
    if not any(r == "board" for r, _ in roles.values()):
        warn("No board-body mesh was recognised, so kicad-cli's mesh naming "
             "may have changed. Board layers are getting component treatment "
             "and the recentre is falling back to all-mesh bounds.")

    # ---- map materials to the roles that use them --------------------------
    mat_roles = {}
    mat_labels = {}
    for mi, mesh in enumerate(meshes):
        role, label = roles[mi]
        for prim in mesh.get("primitives", []):
            if "material" in prim:
                mat_roles.setdefault(prim["material"], set()).add(role)
                mat_labels.setdefault(prim["material"], set()).add(label)

    # ---- material fixes ---------------------------------------------------
    PRETTY = {
        "board": "Board",
        "soldermask": "SolderMask",
        "soldermask_front": "SolderMask_Front",
        "soldermask_back": "SolderMask_Back",
        "silkscreen": "Silkscreen",
        "silkscreen_front": "Silkscreen_Front",
        "silkscreen_back": "Silkscreen_Back",
        "copper": "Copper",
        "pad": "Pads",
        "component": "Component",
    }
    for idx, material in enumerate(materials):
        used_by = mat_roles.get(idx, set())
        board_used = {r for r in used_by if r in BOARD_ROLES}
        if len(used_by) == 1:
            role = next(iter(used_by))
        elif board_used and not used_by - board_used:
            # Shared across board layers only -- tracks and pads commonly
            # share one copper material. Still a board material: it must not
            # keep alphaMode BLEND, must stay out of reach of --metal-colors,
            # and must not be named after its colour. Pick the policy
            # deterministically by role precedence.
            role = sorted(board_used, key=BOARD_ROLES.index)[0]
        else:
            # Genuinely ambiguous (a board layer sharing with a component).
            role = None
        pbr = material.setdefault("pbrMetallicRoughness", {})
        base = pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])

        if not opts.keep_transparency and role in ("board", "soldermask", "silkscreen"):
            if role == "soldermask" and opts.mask_opacity < 1.0:
                # The sorting problem is a *stack* of blended layers. A single
                # blended mask above an opaque board and under opaque
                # silkscreen is drawn after every opaque mesh and depth-tested
                # against them, so it cannot be misordered. Copper under it
                # then shows through tinted, like on a real board.
                make_translucent(material, opts.mask_opacity)
                stats["translucent"] += 1
            elif make_opaque(material):
                stats["opaque"] += 1

        if role == "board":
            set_pbr(material, 0.0, opts.board_roughness)
        elif role == "soldermask":
            set_pbr(material, 0.0, opts.mask_roughness)
        elif role == "silkscreen":
            set_pbr(material, 0.0, opts.silk_roughness)
        elif role in ("copper", "pad"):
            # kicad-cli already emits metallic=1.0 / roughness=0.4 here, which
            # is right for finished copper. Only fill in anything missing.
            if "metallicFactor" not in pbr:
                set_pbr(material, 1.0, None)
            if "roughnessFactor" not in pbr:
                set_pbr(material, None, opts.copper_roughness)
        else:
            # Component materials, or a material shared across roles.
            #
            # An explicit --metal-colors entry wins over the colour heuristic,
            # because no heuristic can settle every case: a single material can
            # serve both a white plastic housing and a nickel-plated connector
            # shell, and then the colour carries no information at all.
            colour = hex_of(base)
            if colour in metal_colours:
                set_pbr(material, opts.metal_metallic, opts.metal_roughness)
                matched_colours.add(colour)
                stats["forced_metal"] += 1
            elif "metallicFactor" not in pbr and "roughnessFactor" not in pbr:
                # Supply PBR values only where kicad-cli left them absent --
                # that absence is what makes glTF fall back to metal=1.0 /
                # rough=1.0.
                if opts.detect_metals and looks_like_bare_metal(base):
                    set_pbr(material, opts.metal_metallic, opts.metal_roughness)
                    stats["metal"] += 1
                else:
                    set_pbr(material, opts.component_metallic, opts.component_roughness)
                stats["pbr_fixed"] += 1

        if not opts.keep_double_sided and material.get("doubleSided"):
            material["doubleSided"] = False
            stats["culled"] += 1

        if not opts.keep_names:
            if role in BOARD_ROLES:
                # Name after the side-specific label where the material belongs
                # to exactly one, so material names line up with node names.
                labels = mat_labels.get(idx, set())
                key = next(iter(labels)) if len(labels) == 1 else role
                new = unique_name(
                    pretty_from_label(key, PRETTY) or "Material", taken_mats)
            else:
                # Name component materials after their colour rather than a
                # running index. An index shifts whenever the board gains or
                # loses a part, which would silently retarget any material
                # override written against it downstream.
                stem = "Component" if role == "component" else "Material"
                new = unique_name(f"{stem}_{hex_of(base)}", taken_mats)
            if material.get("name") != new:
                material["name"] = new
                stats["renamed_mats"] += 1

    # ---- node and mesh names ---------------------------------------------
    if not opts.keep_names:
        # The bare "soldermask"/"silkscreen" keys are what pretty_from_label
        # falls back to for the indeterminate-normal labels (soldermask_0),
        # which would otherwise keep their raw lowercase form.
        NODE_NAMES = {
            "board": "Board",
            "soldermask": "SolderMask",
            "soldermask_front": "SolderMask_Front",
            "soldermask_back": "SolderMask_Back",
            "silkscreen": "Silkscreen",
            "silkscreen_front": "Silkscreen_Front",
            "silkscreen_back": "Silkscreen_Back",
            "copper": "Copper",
            "pad": "Pads",
        }
        taken_nodes = set()

        def owning_refdes(node_idx, ignore=()):
            """Nearest ancestor name that is a reference designator.

            A multi-solid STEP model gets an extra OpenCASCADE assembly node
            between the footprint and its meshes, so the immediate parent is
            not always the reference designator -- for a two-solid connector
            the chain is J3 -> '=>[0:1:1:13]' -> two mesh nodes. Walk up until
            a real name appears.
            """
            seen = set()
            cur = parent_of.get(node_idx)
            while cur is not None and cur not in seen:
                seen.add(cur)
                name = nodes[cur].get("name")
                if name and not is_occt_label(name) and cur not in ignore:
                    return name
                cur = parent_of.get(cur)
            return None

        for mi, mesh in enumerate(meshes):
            role, label = roles[mi]
            node_idx, _ = by_mesh.get(mi, (None, None))
            if node_idx is None:
                continue
            if role == "component":
                # The reference designator lives on an ancestor; give the mesh
                # node a derived name so both are addressable.
                refdes = owning_refdes(node_idx)
                stem = f"{refdes}_Model" if refdes else mesh.get("name", "Component")
                new = unique_name(stem, taken_nodes)
            else:
                # Board roles need unique_name() as much as components do: two
                # meshes can share one label, and a duplicate name is not
                # addressable from engine script.
                new = unique_name(
                    pretty_from_label(label, NODE_NAMES) or label, taken_nodes)
                mesh["name"] = new
            if nodes[node_idx].get("name") != new:
                nodes[node_idx]["name"] = new
                stats["renamed_nodes"] += 1

        # Any intermediate OpenCASCADE assembly node left over is still
        # unaddressable, so name it after the part it belongs to.
        # Snapshot the set first and have the walk ignore it. The loop writes
        # names that owning_refdes() would otherwise read straight back, so a
        # chain three levels deep would yield 'J3_Assembly_Assembly'. A node
        # carrying a mesh is not an assembly -- it is an instanced mesh the
        # pass above skipped, since build_node_index keeps one node per mesh.
        occt_nodes = [
            i for i, node in enumerate(nodes)
            if is_occt_label(node.get("name", "")) and "mesh" not in node
        ]
        occt_set = set(occt_nodes)
        for i in occt_nodes:
            refdes = owning_refdes(i, ignore=occt_set)
            nodes[i]["name"] = unique_name(
                f"{refdes}_Assembly" if refdes else "Assembly", taken_nodes
            )
            stats["renamed_nodes"] += 1

    # ---- recentre and scale ----------------------------------------------
    if opts.center or opts.scale != 1.0:
        # Prefer the board body's bounds: components should not drag the pivot
        # off the board.
        board_bounds = None
        for mi, mesh in enumerate(meshes):
            if roles[mi][0] == "board":
                board_bounds = mesh_bounds(gltf, mesh)
                break
        if board_bounds is None:
            for mi, mesh in enumerate(meshes):
                b = mesh_bounds(gltf, mesh)
                if b is None:
                    continue
                if board_bounds is None:
                    board_bounds = b
                else:
                    board_bounds = (
                        [min(a, c) for a, c in zip(board_bounds[0], b[0])],
                        [max(a, c) for a, c in zip(board_bounds[1], b[1])],
                    )

        if board_bounds is None:
            warn("Could not determine bounds; skipping recentre/scale.")
        else:
            lo, hi = board_bounds
            centre = [(lo[i] + hi[i]) / 2.0 for i in range(3)]
            size = [hi[i] - lo[i] for i in range(3)]

            scenes = gltf.setdefault("scenes", [{"nodes": []}])
            scene = scenes[gltf.get("scene", 0)]
            old_roots = list(scene.get("nodes", []))

            # kicad-cli emits a single unnamed, untransformed grouping node at
            # the root. Reuse it when that is what we find, so we don't leave a
            # redundant node in the hierarchy; otherwise wrap, so that any
            # transform already present survives.
            reusable = (
                len(old_roots) == 1
                and not nodes[old_roots[0]].get("name")
                and "mesh" not in nodes[old_roots[0]]
                and not any(k in nodes[old_roots[0]]
                            for k in ("matrix", "translation", "rotation", "scale"))
            )
            if reusable:
                target = nodes[old_roots[0]]
            else:
                target = {"children": old_roots}
                nodes.append(target)
                scene["nodes"] = [len(nodes) - 1]

            target["name"] = opts.root_name or "PCB"
            if opts.center:
                # glTF composes a node transform as M = T * R * S, so the
                # translation is applied *after* the scale. Pre-multiply it, or
                # the pivot ends up (scale - 1) * centre away from the board --
                # at the documented scale of 1000 that is the whole defect the
                # recentre exists to remove, just 1000x larger.
                target["translation"] = [
                    round(-c * opts.scale, 9) for c in centre
                ]
            if opts.scale != 1.0:
                target["scale"] = [opts.scale] * 3

            log(f"board size: {size[0]*1000:.1f} x {size[2]*1000:.1f} x "
                f"{size[1]*1000:.2f} mm (glTF units are metres)")
            if opts.center:
                applied = target["translation"]
                log(f"recentred by [{applied[0]:.4f}, {applied[1]:.4f}, "
                    f"{applied[2]:.4f}]")
            if opts.scale != 1.0:
                log(f"scaled by {opts.scale}")
    elif opts.root_name:
        scenes = gltf.setdefault("scenes", [{"nodes": []}])
        scene = scenes[gltf.get("scene", 0)]
        for r in scene.get("nodes", []):
            if not nodes[r].get("name"):
                nodes[r]["name"] = opts.root_name

    unmatched = sorted(metal_colours - matched_colours)
    if unmatched:
        warn("These --metal-colors matched no component material, so they had "
             "no effect: " + ", ".join(unmatched))

    return stats


def build_parser():
    p = argparse.ArgumentParser(
        prog="postprocess.py",
        description="Make a kicad-cli GLB export render well in real-time engines.",
    )
    p.add_argument("input", help="input .glb produced by kicad-cli")
    p.add_argument("-o", "--output", help="output path (default: edit in place)")
    p.add_argument("--root-name", default="PCB", help="name for the root node")

    p.add_argument("--center", dest="center", action="store_true", default=True,
                   help="recentre the model on the board bounding box (default)")
    p.add_argument("--no-center", dest="center", action="store_false",
                   help="keep kicad-cli's origin")
    p.add_argument("--scale", type=float, default=1.0,
                   help="uniform scale applied to the root node (default 1.0, metres)")

    p.add_argument("--keep-transparency", action="store_true",
                   help="leave board/mask/silkscreen as alphaMode BLEND")
    p.add_argument("--mask-opacity", type=float, default=1.0,
                   help="soldermask opacity, above 0 and up to 1 (default 1.0, "
                        "opaque). Below 1 the mask alone stays blended so copper "
                        "under it shows through tinted; 0.83 is KiCad's own value")
    p.add_argument("--keep-double-sided", action="store_true",
                   help="leave backface culling disabled")
    p.add_argument("--keep-names", action="store_true",
                   help="leave OpenCASCADE node and mat_N material names alone")

    p.add_argument("--detect-metals", dest="detect_metals", action="store_true",
                   default=True, help="treat unsaturated mid-grey component "
                                      "colours as bare metal (default)")
    p.add_argument("--no-detect-metals", dest="detect_metals", action="store_false",
                   help="treat every component material as a dielectric")
    p.add_argument("--metal-colors", default="",
                   help="comma-separated hex colours whose component materials "
                        "are forced metallic, e.g. 'EDBE51,97A3DA'. Overrides "
                        "the colour heuristic. Board layers are never affected, "
                        "so listing FFFFFF cannot make the silkscreen metallic.")

    p.add_argument("--board-roughness", type=float, default=0.85)
    p.add_argument("--mask-roughness", type=float, default=0.45)
    p.add_argument("--silk-roughness", type=float, default=0.9)
    p.add_argument("--copper-roughness", type=float, default=0.4)
    p.add_argument("--component-metallic", type=float, default=0.0)
    p.add_argument("--component-roughness", type=float, default=0.5)
    p.add_argument("--metal-metallic", type=float, default=0.9)
    p.add_argument("--metal-roughness", type=float, default=0.35)
    return p


def main(argv=None):
    opts = build_parser().parse_args(argv)
    if not 0.0 < opts.mask_opacity <= 1.0:
        print(f"::error::--mask-opacity must be above 0 and up to 1, got {opts.mask_opacity}.")
        return 1
    src = Path(opts.input)
    if not src.is_file():
        print(f"::error::GLB post-process input '{src}' not found.")
        return 1

    try:
        gltf, binary = read_glb(src)
    except (ValueError, json.JSONDecodeError, struct.error) as exc:
        print(f"::error::Could not read '{src}': {exc}")
        return 1

    before = src.stat().st_size
    print(f"Post-processing '{src.name}' for real-time rendering:")
    stats = process(gltf, binary, opts)

    dest = Path(opts.output) if opts.output else src
    try:
        after = write_glb(dest, gltf, binary)
    except OSError as exc:
        print(f"::error::Could not write '{dest}': {exc}")
        return 1

    log(f"{stats['pbr_fixed']} component materials given PBR values "
        f"({stats['metal']} detected as bare metal)")
    if stats["forced_metal"]:
        log(f"{stats['forced_metal']} materials forced metallic by --metal-colors")
    log(f"{stats['opaque']} materials forced opaque, "
        f"{stats['culled']} switched to backface culling")
    if stats["translucent"]:
        log(f"{stats['translucent']} soldermask materials kept translucent "
            f"at opacity {opts.mask_opacity:g}")
    log(f"renamed {stats['renamed_nodes']} nodes and {stats['renamed_mats']} materials")
    notice(f"GLB post-processed: {dest.name} ({before/1024:.1f} KiB -> {after/1024:.1f} KiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
