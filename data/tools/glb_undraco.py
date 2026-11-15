# Convierte modelos .glb con compresión Draco (que Godot no lee) en .glb normales,
# y aligera los muy pesados con un modificador Decimate.
# Uso (Blender sin ventana):
#   blender -b --factory-startup --python data/tools/glb_undraco.py -- <entrada.glb> <salida.glb> [max_triangulos]
import sys
import bpy

args = sys.argv[sys.argv.index("--") + 1:]
src, dst = args[0], args[1]
max_tris = int(args[2]) if len(args) > 2 else 0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
print(f"[undraco] {src}: {len(meshes)} mallas, {tris} triangulos")

if max_tris and tris > max_tris:
    ratio = max(0.05, max_tris / tris)
    for o in meshes:
        if len(o.data.polygons) < 200:
            continue  # piezas chicas: se dejan como están
        mod = o.modifiers.new("decimar", "DECIMATE")
        mod.ratio = ratio
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    tris2 = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
    print(f"[undraco] decimado a {ratio:.2f}: {tris2} triangulos")

bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_draco_mesh_compression_enable=False)
print(f"[undraco] guardado {dst}")
