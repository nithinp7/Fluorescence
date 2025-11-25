
import flrlib
import struct
import numpy as np
import fbx
import os

fbx_manager : fbx.FbxManager
fbx_scene : fbx.FbxScene
fbx_importer : fbx.FbxImporter

fbx_meshes = []
fbx_vertices = []
fbx_normals = []

def collect_meshes(node : fbx.FbxNode):
  mesh = node.GetMesh()
  if mesh:
    fbx_meshes.append(mesh)
    # TODO actually use an index buffer...
    for i in range(mesh.GetPolygonCount()):
      polyVertCount = mesh.GetPolygonSize(i)
      indices = []
      if polyVertCount == 3:
        indices = [0, 1, 2]
      elif polyVertCount == 4:
        indices = [0, 1, 2, 0, 2, 3]
      else:
        exit(1)
      
      for j in indices:
        vidx = mesh.GetPolygonVertex(i, j)
        fbx_vertices.append(mesh.GetControlPointAt(vidx))
        fbx_normals.append(fbx.FbxVector4())
        mesh.GetPolygonVertexNormal(i, j, fbx_normals[-1])
          
    print(mesh)
  for i in range(node.GetChildCount()):
    collect_meshes(node.GetChild(i))
  
def print_node(node : fbx.FbxNode):
  print(f"  - {node.GetName()}")
  for i in range(node.GetChildCount()):
    print_node(node.GetChild(i))
  
def load_fbx(fbx_path : str):
  global fbx_manager
  global fbx_scene
  global fbx_importer
  fbx_manager = fbx.FbxManager.Create()
  fbx_scene = fbx.FbxScene.Create(fbx_manager, "MyScene")
  fbx_importer = fbx.FbxImporter.Create(fbx_manager, "")
  if not fbx_importer.Initialize(fbx_path, -1):
    print("Import failed")
    return False

  if not fbx_importer.Import(fbx_scene):
    print("Failed scene import")
    return False

  root_node = fbx_scene.GetRootNode()
  if root_node:
    collect_meshes(root_node)
    print_node(root_node)

  return True

def destroy_fbx():
  fbx_importer.Destroy()
  fbx_manager.Destroy()

fbx_res = load_fbx(os.path.abspath("fbx/BetaCharacter.fbx"))
if not fbx_res:
  exit(1)

vert_count = len(fbx_vertices)

params = flrlib.FlrParams()
params.append("VERT_COUNT", vert_count)
flr = flrlib.FlrScriptInterface("FlrProject/AnimSandbox.flr", params, flrDebugEnable = True)

positionsHandle = flr.getBufferHandle("positions")
normalsHandle = flr.getBufferHandle("normals")
testSlider = flr.getSliderFloatHandle("TEST_SLIDER")

def initProject():
  buf = bytearray(vert_count * 4 * 3)
  for i in range(0, vert_count):
    v = fbx_vertices[i]
    buf[12*i:12*(i+1)] = struct.pack("<fff", v[0], v[1], v[2])
  flr.cmdBufferStagedUpload(positionsHandle, 0, buf)
  for i in range(0, vert_count):
    v = fbx_normals[i]
    buf[12*i:12*(i+1)] = struct.pack("<fff", v[0], v[1], v[2])
  flr.cmdBufferStagedUpload(normalsHandle, 0, buf)

  print("Initializing AnimSandbox...")

initProject()

sliderVal = 0.0
t = 0.0
DT = 1.0/30.0
while True:
  v = flr.getSliderFloat(testSlider)
  if v != sliderVal:
    sliderVal = v
    print(v)
  t += DT
  match flr.tick():
    case flrlib.FlrTickResult.TR_REINIT:
      initProject()
    case flrlib.FlrTickResult.TR_TERMINATE:
      break

destroy_fbx()

exit(0) 