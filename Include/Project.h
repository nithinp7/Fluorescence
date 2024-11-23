#pragma once

#include "Shared/CommonStructures.h"

#include <Althea/Application.h>
#include <Althea/BindlessHandle.h>
#include <Althea/BufferUtilities.h>
#include <Althea/ComputePipeline.h>
#include <Althea/FrameContext.h>
#include <Althea/Framebuffer.h>
#include <Althea/GlobalHeap.h>
#include <Althea/PerFrameResources.h>
#include <Althea/RenderPass.h>
#include <Althea/StructuredBuffer.h>
#include <Althea/TransientUniforms.h>
#include <vulkan/vulkan.h>

#include <cstdint>
#include <string>
#include <vector>

using namespace AltheaEngine;

namespace flr {
struct ParsedFlr {
  ParsedFlr(const char* projectPath);

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

  struct Draw {
    // TODO: re-usable subpasses that can be used multiple times...
    std::string vertexShader;
    std::string pixelShader;
    uint32_t vertexCount;
    uint32_t instanceCount;
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
    TT_RENDER
  };
  struct Task {
    uint32_t idx;
    TaskType type;
  };
  std::vector<Task> m_taskList;

  bool m_failed;
  char m_errMsg[2048];

  enum Instr : uint8_t {
    I_CONST_UINT = 0,
    I_CONST_INT,
    I_CONST_FLOAT,
    I_STRUCT,
    I_STRUCT_SIZE,
    I_STRUCTURED_BUFFER,
    I_COMPUTE_SHADER,
    I_COMPUTE_DISPATCH,
    I_BARRIER,
    I_DISPLAY_PASS,
    I_RENDER_PASS,
    I_DRAW,
    I_COUNT
  };

  static constexpr char* INSTR_NAMES[I_COUNT] = {
      "uint",
      "int",
      "float",
      "struct",
      "struct_size",
      "structured_buffer",
      "compute_shader",
      "compute_dispatch",
      "barrier",
      "display_pass",
      "render_pass",
      "draw"};
};

class Project {
public:
  Project(
      Application& app,
      GlobalHeap& heap,
      const TransientUniforms<FlrUniforms>& flrUniforms,
      const char* projectPath);

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

  const char* getErrorMessage() const {
    return m_parsed.m_errMsg;
  }

  bool hasRecompileFailed() const { return m_failedShaderCompile; }

  const char* getShaderCompileErrors() const {
    return m_shaderCompileErrMsg;
  }

  void tryRecompile(Application& app);

private:
  ParsedFlr m_parsed;

  std::vector<BufferAllocation> m_buffers;
  std::vector<ComputePipeline> m_computePipelines;

  struct DrawTask {
    uint32_t renderpassIdx;
    uint32_t subpassIdx;
    uint32_t vertexCount;
    uint32_t instanceCount;
  };

  struct DrawPass {
    ImageResource m_target;
    RenderPass m_renderPass;
    FrameBuffer m_frameBuffer;
  };
  std::vector<DrawPass> m_drawPasses;

  PerFrameResources m_descriptorSets;

  uint32_t m_displayPassIdx;

  bool m_failedShaderCompile;
  char m_shaderCompileErrMsg[2048];
};
} // namespace flr