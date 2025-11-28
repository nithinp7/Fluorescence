
import flrlib
import struct
import fbx
import os

def printMatrix(mat : fbx.FbxAMatrix):
  print("Print Mat:")
  print(f"\t{mat.Get(0, 0)}, {mat.Get(1, 0)}, {mat.Get(2, 0)}, {mat.Get(3, 0)},")
  print(f"\t{mat.Get(0, 1)}, {mat.Get(1, 1)}, {mat.Get(2, 1)}, {mat.Get(3, 1)},")
  print(f"\t{mat.Get(0, 2)}, {mat.Get(1, 2)}, {mat.Get(2, 2)}, {mat.Get(3, 2)},")
  print(f"\t{mat.Get(0, 3)}, {mat.Get(1, 3)}, {mat.Get(2, 3)}, {mat.Get(3, 3)}")

def flatten_nodes(node : fbx.FbxNode, nodes):
  nodes.append(node)
  for i in range(node.GetChildCount()):
    flatten_nodes(node.GetChild(i), nodes)

model_path = os.path.abspath("fbx/BetaCharacter.fbx")
anim_path = os.path.abspath("fbx/back_flip_to_uppercut.fbx")

fbx_manager = fbx.FbxManager.Create()
fbx_scene = fbx.FbxScene.Create(fbx_manager, "ModelScene")
anim_scene = fbx.FbxScene.Create(fbx_manager, "AnimScene")

fbx_importer = fbx.FbxImporter.Create(fbx_manager, "ModelImporter")
anim_importer = fbx.FbxImporter.Create(fbx_manager, "AnimImporter")

fbx_importer.Initialize(model_path, -1)
anim_importer.Initialize(anim_path, -1)

fbx_importer.Import(fbx_scene)
anim_importer.Import(anim_scene)

fbx_nodes = []
flatten_nodes(fbx_scene.GetRootNode(), fbx_nodes)
anim_nodes = []
flatten_nodes(anim_scene.GetRootNode(), anim_nodes)

assert(len(fbx_nodes) >= len(anim_nodes))
scene_to_anim_nodes = []
for sn in fbx_nodes:
  for i in range(len(anim_nodes)):
    if sn.GetName() == anim_nodes[i].GetName():
      scene_to_anim_nodes.append(i)
      break
  else:
    print(f"Matching node not found for {sn.GetName()}")
    scene_to_anim_nodes.append(-1)

print(f"Num AnimStacks {anim_importer.GetAnimStackCount()}")
take_info = anim_importer.GetTakeInfo(0)

anim = fbx.FbxAnimStack.Create(anim_scene, "MyAnimStack")
anim.Reset(take_info)
evaluator = anim_scene.GetAnimationEvaluator()

fbx_meshes = []
for node in fbx_nodes:
  mesh = node.GetMesh()
  if mesh:
    fbx_meshes.append(mesh)

fbx_indexBuffer = []
fbx_vertices = []
fbx_normals = []

vertex_offsets = []
index_offsets = []
for mesh in fbx_meshes:
  vertexOffset = len(fbx_vertices)
  vertex_offsets.append(vertexOffset)
  for i in range(mesh.GetControlPointsCount()):
    fbx_vertices.append(mesh.GetControlPointAt(i))
    fbx_normals.append(fbx.FbxVector4())

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
      vidx = vertexOffset + mesh.GetPolygonVertex(i, j)
      assert(vidx < len(fbx_vertices))
      # TODO This does not look correct, each poly is stomping over shared normals..
      mesh.GetPolygonVertexNormal(i, j, fbx_normals[vidx])
      fbx_indexBuffer.append(vidx)

vert_count = len(fbx_vertices)
index_count = len(fbx_indexBuffer)

MAX_INFLUENCES = 8

fbx_skinIndices = [0] * (MAX_INFLUENCES * vert_count)
fbx_skinWeights = [0.0] * (MAX_INFLUENCES * vert_count)
fbx_skinInfluenceCounts = [0] * vert_count

fbx_deformers = []
fbx_clusters = []
cluster_to_node = []
bind_matrices = []
for midx in range(len(fbx_meshes)):
  mesh = fbx_meshes[midx]
  vertexOffset = vertex_offsets[midx]
  for i in range(mesh.GetDeformerCount()):
    deformer = mesh.GetDeformer(i)
    fbx_deformers.append(deformer)
    for j in range(deformer.GetClusterCount()):
      cluster = deformer.GetCluster(j)
      
      lMatrix = fbx.FbxAMatrix()
      cluster.GetTransformMatrix(lMatrix)
      linkMatrix = fbx.FbxAMatrix()
      cluster.GetTransformLinkMatrix(linkMatrix)
      bind_matrices.append(linkMatrix.Inverse() * lMatrix)

      for nodeIdx in range(len(fbx_nodes)):
        if fbx_nodes[nodeIdx] == cluster.GetLink():
          cluster_to_node.append(nodeIdx)
          break
      else:
        exit(1)
      
      clusterIdx = len(fbx_clusters)
      for k in range(cluster.GetControlPointIndicesCount()):
        vidx = vertexOffset + cluster.GetControlPointIndices()[k]
        influenceIdx = fbx_skinInfluenceCounts[vidx]
        for l in range(influenceIdx):
          if fbx_skinIndices[MAX_INFLUENCES*vidx + l] == clusterIdx:
            break
        else:
          assert(influenceIdx < MAX_INFLUENCES)
          fbx_skinInfluenceCounts[vidx] = influenceIdx + 1
          fbx_skinIndices[MAX_INFLUENCES*vidx + influenceIdx] = clusterIdx
          fbx_skinWeights[MAX_INFLUENCES*vidx + influenceIdx] = cluster.GetControlPointWeights()[k]
      fbx_clusters.append(cluster)

# TODO get rid of extra matrices
matrices = [None] * 3 * len(fbx_clusters)

def updateMatrices(t : float):
  time = fbx.FbxTime()
  time.SetSecondDouble(t)
  for i in range(len(fbx_clusters)):
    anidx = scene_to_anim_nodes[cluster_to_node[i]]
    assert(anidx >= 0)
    node = anim_nodes[anidx]
    
    matrices[i] = node.EvaluateGlobalTransform(time) * bind_matrices[i]

  buf = bytearray(matrices_count * 64)
  for matIdx in range(matrices_count):
    mat = matrices[matIdx]
    if mat != None:
      for col in range(4):
        offs = 64*matIdx + 16*col
        buf[offs:offs+16] = struct.pack("<ffff", mat.Get(col, 0), mat.Get(col, 1), mat.Get(col, 2), mat.Get(col, 3))
  flr.cmdBufferWrite(matricesHandle, 0xFFFFFFFF, 0, buf)

print(f"Num Nodes: {len(fbx_nodes)}")
print(f"Num Verts: {vert_count}")
print(f"Num Indices: {index_count}")
print(f"Num Deformers: {len(fbx_deformers)}")
print(f"Num Clusters: {len(fbx_clusters)}")

matrices_count = len(matrices)

params = flrlib.FlrParams()
params.append("INDEX_COUNT", index_count)
params.append("VERT_COUNT", vert_count)
params.append("BONE_COUNT", len(fbx_clusters))
params.append("MATRICES_COUNT", matrices_count)
params.append("MAX_INFLUENCES", MAX_INFLUENCES)
flr = flrlib.FlrScriptInterface("FlrProject/AnimSandbox.flr", params, flrDebugEnable = True)

# buffer handles
indexBufferHandle = flr.getBufferHandle("indexBuffer")
positionsHandle = flr.getBufferHandle("positions")
normalsHandle = flr.getBufferHandle("normals")
blendIndicesHandle = flr.getBufferHandle("blendIndices")
blendWeightsHandle = flr.getBufferHandle("blendWeights")
matricesHandle = flr.getBufferHandle("matrices")

# ui handles
timeSlider = flr.getSliderFloatHandle("ANIM_TIME")
frameSlider = flr.getSliderUintHandle("ANIM_FRAME")
boneInfluenceSlider = flr.getSliderIntHandle("SELECT_BONE_INFLUENCE")
loopCheckbox = flr.getCheckboxHandle("LOOP_ANIM")

def initProject():
  buf = bytearray(index_count * 4)
  for i in range(len(fbx_indexBuffer)):
    buf[4*i:4*i+4] = struct.pack("<I", fbx_indexBuffer[i])
  flr.cmdBufferStagedUpload(indexBufferHandle, 0, buf)

  buf = bytearray(vert_count * 4 * 3)
  for i in range(vert_count):
    v = fbx_vertices[i]
    buf[12*i:12*(i+1)] = struct.pack("<fff", v[0], v[1], v[2])
  flr.cmdBufferStagedUpload(positionsHandle, 0, buf)

  for i in range(vert_count):
    v = fbx_normals[i]
    buf[12*i:12*(i+1)] = struct.pack("<fff", v[0], v[1], v[2])
  flr.cmdBufferStagedUpload(normalsHandle, 0, buf)

  buf = bytearray(vert_count * MAX_INFLUENCES * 4)
  for i in range(vert_count):
    for j in range(MAX_INFLUENCES):
      offs = MAX_INFLUENCES * 4 * i + 4 * j
      buf[offs:offs+4] = struct.pack("<I", fbx_skinIndices[MAX_INFLUENCES*i + j])
  flr.cmdBufferStagedUpload(blendIndicesHandle, 0, buf)

  for i in range(vert_count):
    for j in range(MAX_INFLUENCES):
      offs = MAX_INFLUENCES * 4 * i + 4 * j
      buf[offs:offs+4] = struct.pack("<f", fbx_skinWeights[MAX_INFLUENCES*i + j])
  flr.cmdBufferStagedUpload(blendWeightsHandle, 0, buf)

  print("Initializing AnimSandbox...")

initProject()

prevBoneInfluenceSliderValue = -1

t = 0.0
DT = 1.0 / 30.0
while True:
  boneInfluenceSliderValue = flr.getSliderInt(boneInfluenceSlider)
  if boneInfluenceSliderValue != prevBoneInfluenceSliderValue:
    prevBoneInfluenceSliderValue = boneInfluenceSliderValue
    if -1 < boneInfluenceSliderValue < len(matrices):
      anidx = scene_to_anim_nodes[cluster_to_node[boneInfluenceSliderValue]]
      print(f"Selected Bone: {anim_nodes[anidx].GetName()}")
  
  if flr.getCheckbox(loopCheckbox):
    t += DT
    if t > 8.0:
      t = 0.0
  else:
    t = flr.getSliderFloat(timeSlider)
  
  updateMatrices(t)
  match flr.tick():
    case flrlib.FlrTickResult.TR_REINIT:
      initProject()
    case flrlib.FlrTickResult.TR_TERMINATE:
      break

fbx_importer.Destroy()
fbx_manager.Destroy()

exit(0) 