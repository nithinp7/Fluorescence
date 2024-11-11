#pragma once

#include <Althea/ComputePipeline.h>
#include <Althea/RenderPass.h>
#include <Althea/StructuredBuffer.h>
#include <Althea/BufferUtilities.h>
#include <Althea/Framebuffer.h>

#include <cstdint>
#include <vector>
#include <string>

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

  struct BufferDesc {
    std::string name;
    uint32_t elemSize;
    uint32_t elemCount;
  };
  std::vector<BufferDesc> m_buffers;

  std::vector<std::string> m_computeShaders;

  struct ComputeDispatch {
    uint32_t computeShaderIndex;
    uint32_t dispatchSizeX;
    uint32_t dispatchSizeY;
    uint32_t dispatchSizeZ;
  };
  std::vector<ComputeDispatch> m_computeDispatches;

  struct Barrier {
    uint32_t bufferIdx;
  };
  std::vector<Barrier> m_barriers;

  struct DisplayPass {
    std::string vertexShader;
    std::string pixelShader;
  };
  std::vector<DisplayPass> m_displayPasses;

  enum TaskType : uint8_t {
    TT_COMPUTE = 0,
    TT_BARRIER,
    TT_DISPLAY,
  };
  struct Task {
    uint32_t idx;
    TaskType type;
  };
  std::vector<Task> m_taskList;

  enum Instr : uint8_t {
    I_CONST_UINT = 0,
    I_CONST_INT,
    I_CONST_FLOAT,
    I_STRUCTURED_BUFFER,
    I_COMPUTE_STAGE,
    I_BARRIER,
    I_DISPLAY_PASS,
    I_COUNT
  };

  static constexpr char* INSTR_NAMES[I_COUNT] = {
    "uint",
    "int",
    "float",
    "structured_buffer",
    "compute_stage",
    "barrier",
    "display_pass"
  };

  std::vector<std::string> m_extraDefines;
};

class Project {
public:
  Project(const char* projectPath);

private:
  ParsedFlr m_parsed;

  std::vector<BufferAllocation> m_buffers;

  struct ComputeStage {
    std::vector<ComputePipeline> m_computeTasks;
  };

  RenderPass m_renderPass;
  FrameBuffer m_frameBuffer;
};
} // namespace flr