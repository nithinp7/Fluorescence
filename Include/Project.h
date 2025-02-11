#pragma once

#include "Shared/CommonStructures.h"
#include "SimpleObjLoader.h"

#include <Althea/Application.h>
#include <Althea/BindlessHandle.h>
#include <Althea/BufferUtilities.h>
#include <Althea/ComputePipeline.h>
#include <Althea/FrameContext.h>
#include <Althea/Framebuffer.h>
#include <Althea/GlobalHeap.h>
#include <Althea/ImageResource.h>
#include <Althea/PerFrameResources.h>
#include <Althea/RenderPass.h>
#include <Althea/StructuredBuffer.h>
#include <Althea/TransientUniforms.h>
#include <vulkan/vulkan.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

using namespace AltheaEngine;

namespace flr {
class Audio;

struct ParsedFlr {
  ParsedFlr(Application& app, const char* projectPath);

  struct ConstUint {
    std::string name;
    uint32_t value;
  };
  std::vector<ConstUint> m_constUints;

  struct ConstInt {
    std::string name;
    int value;
  };
  std::vector<ConstInt> m_constInts;

  struct ConstFloat {
    std::string name;
    float value;
  };
  std::vector<ConstFloat> m_constFloats;

  struct SliderUint {
    std::string name;
    uint32_t defaultValue;
    uint32_t min;
    uint32_t max;
    uint32_t uiIdx;
    uint32_t* pValue;
  };
  std::vector<SliderUint> m_sliderUints;

  struct SliderInt {
    std::string name;
    int defaultValue;
    int min;
    int max;
    uint32_t uiIdx;
    int* pValue;
  };
  std::vector<SliderInt> m_sliderInts;

  struct SliderFloat {
    std::string name;
    float defaultValue;
    float min;
    float max;
    uint32_t uiIdx;
    float* pValue;
  };
  std::vector<SliderFloat> m_sliderFloats;

  struct Checkbox {
    std::string name;
    bool defaultValue;
    uint32_t uiIdx;
    uint32_t* pValue; // glsl bools are 32bit
  };
  std::vector<Checkbox> m_checkboxes;

  struct StructDef {
    std::string name;
    std::string body;
    uint32_t size;
  };
  std::vector<StructDef> m_structDefs;

  struct BufferDesc {
    std::string name;
    uint32_t structIdx;
    uint32_t elemCount;
  };
  std::vector<BufferDesc> m_buffers;

  struct ImageDesc {
    std::string name;
    std::string format;
    ImageOptions createOptions;
  };
  std::vector<ImageDesc> m_images;

  struct TextureDesc {
    std::string name;
    uint32_t imageIdx; // TODO: allow for textures loaded from files
  };
  std::vector<TextureDesc> m_textures;

  struct ComputeShader {
    std::string name;
    uint32_t groupSizeX;
    uint32_t groupSizeY;
    uint32_t groupSizeZ;
  };
  std::vector<ComputeShader> m_computeShaders;

  struct ComputeDispatch {
    uint32_t computeShaderIndex;
    uint32_t dispatchSizeX;
    uint32_t dispatchSizeY;
    uint32_t dispatchSizeZ;
  };
  std::vector<ComputeDispatch> m_computeDispatches;

  struct Barrier {
    std::vector<uint32_t> buffers;
  };
  std::vector<Barrier> m_barriers;

  struct ObjMesh {
    std::string name;
    std::string path;
  };
  std::vector<ObjMesh> m_objModels;

  enum LayoutTransitionTarget : uint8_t { LTT_TEXTURE = 0, LTT_IMAGE_RW, LTT_ATTACHMENT };
  static constexpr char* TRANSITION_TARGET_NAMES[] = {
    "texture",
    "image",
    "attachment"
  };
  struct Transition {
    uint32_t image;
    LayoutTransitionTarget transitionTarget;
  };
  std::vector<Transition> m_transitions;

  struct Draw {
    // TODO: re-usable subpasses that can be used multiple times...
    std::string vertexShader;
    std::string pixelShader;
    uint32_t vertexCount;
    uint32_t instanceCount;
    int32_t objMeshIdx; // if >= 0, pulls vertex count from loaded file
    bool bDisableDepth;
  };

  struct RenderPass {
    std::vector<Draw> draws;
    uint32_t width;
    uint32_t height;
    bool bIsDisplayPass;
  };
  std::vector<RenderPass> m_renderPasses;

  enum TaskType : uint8_t {
    TT_COMPUTE = 0,
    TT_BARRIER,
    TT_RENDER,
    TT_TRANSITION
  };
  struct Task {
    uint32_t idx;
    TaskType type;
  };
  std::vector<Task> m_taskList;

  enum FeatureFlag : uint32_t {
    FF_NONE = 0,
    FF_PERSPECTIVE_CAMERA = (1 << 0),
    FF_SYSTEM_AUDIO_INPUT = (1 << 1)
  };
  uint32_t m_featureFlags;

  bool isFeatureEnabled(FeatureFlag feature) const {
    return (m_featureFlags & feature) != 0;
  }

  static constexpr char* FEATURE_FLAG_NAMES[] = {
      "perspective_camera",
      "system_audio_input" // TODO: mic audio input
  };

  bool m_failed;
  char m_errMsg[2048];

  enum Instr : uint8_t {
    I_CONST_UINT = 0,
    I_CONST_INT,
    I_CONST_FLOAT,
    I_SLIDER_UINT,
    I_SLIDER_INT,
    I_SLIDER_FLOAT,
    I_CHECKBOX,
    I_STRUCT,
    I_STRUCT_SIZE,
    I_STRUCTURED_BUFFER,
    I_COMPUTE_SHADER,
    I_COMPUTE_DISPATCH,
    I_BARRIER,
    I_OBJ_MODEL,
    I_DISPLAY_PASS,
    I_RENDER_PASS,
    I_DISABLE_DEPTH,
    I_DRAW,
    I_DRAW_OBJ,
    I_FEATURE,
    I_IMAGE,
    I_TEXTURE_ALIAS,
    I_TRANSITION,
    I_COUNT
  };

  static constexpr char* INSTR_NAMES[I_COUNT] = {
      "uint",
      "int",
      "float",
      "slider_uint",
      "slider_int",
      "slider_float",
      "checkbox",
      "struct",
      "struct_size",
      "structured_buffer",
      "compute_shader",
      "compute_dispatch",
      "barrier",
      "obj_model",
      "display_pass",
      "render_pass",
      "disable_depth",
      "draw",
      "draw_obj",
      "enable_feature",
      "image",
      "texture_alias",
      "transition_layout"};
};

class Project {
public:
  Project(
      Application& app,
      GlobalHeap& heap,
      const TransientUniforms<FlrUniforms>& flrUniforms,
      const char* projectPath);
  ~Project();

  void tick(Application& app, const FrameContext& frame);

  void draw(
      Application& app,
      VkCommandBuffer commandBuffer,
      const GlobalHeap& heap,
      const FrameContext& frame);

  TextureHandle getOutputTexture() const {
    return m_drawPasses[m_displayPassIdx].m_target.textureHandle;
  }

  bool isReady() const { return !hasFailed() && !hasRecompileFailed(); }

  bool hasFailed() const { return m_parsed.m_failed; }

  const char* getErrorMessage() const { return m_parsed.m_errMsg; }

  bool hasRecompileFailed() const { return m_failedShaderCompile; }

  const char* getShaderCompileErrors() const { return m_shaderCompileErrMsg; }

  void tryRecompile(Application& app);

private:
  ParsedFlr m_parsed;

  std::vector<BufferAllocation> m_buffers;
  std::vector<ImageResource> m_images;
  std::vector<ComputePipeline> m_computePipelines;

  struct DrawTask {
    uint32_t renderpassIdx;
    uint32_t subpassIdx;
    uint32_t vertexCount;
    uint32_t instanceCount;
  };

  struct DrawPass {
    ImageResource m_target;
    ImageResource m_depth;
    RenderPass m_renderPass;
    FrameBuffer m_frameBuffer;
  };
  std::vector<DrawPass> m_drawPasses;

  PerFrameResources m_descriptorSets;
  DynamicBuffer m_dynamicUniforms;
  std::vector<std::byte> m_dynamicDataBuffer;

  CameraController m_cameraController;
  TransientUniforms<PerspectiveCamera> m_perspectiveCamera;
  TransientUniforms<AudioInput> m_audioInput;

  std::vector<SimpleObjLoader::LoadedObj> m_objModels;

  std::unique_ptr<Audio> m_pAudio;

  uint32_t m_displayPassIdx;

  bool m_bHasDynamicData;

  bool m_failedShaderCompile;
  char m_shaderCompileErrMsg[2048];
};
} // namespace flr