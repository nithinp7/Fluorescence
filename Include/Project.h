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
class Project {
public:
  Project(const char* projectPath);

private:

  enum Instr : uint8_t {
    I_CONST_UINT = 0,
    I_CONST_FLOAT,
    I_STRUCTURED_BUFFER,
    I_COMPUTE_STAGE,
    I_BARRIER,
    I_DISPLAY_PASS,
    I_COUNT
  };

  static constexpr char* INSTR_NAMES[I_COUNT] = {
    "uint",
    "float",
    "structured_buffer",
    "compute_stage",
    "barrier",
    "display_pass"
  };

  void parseFlrFile(const char* filename);

  enum TaskType : uint8_t {
    CT_COMPUTE = 0,
    CT_BARRIER,
    CT_DISPLAY,
  };
  
  std::vector<std::string> m_extraDefines;
  std::vector<BufferAllocation> m_buffers;

  struct ComputeStage {
    std::vector<ComputePipeline> m_computeTasks;
  };

  RenderPass m_renderPass;
  FrameBuffer m_frameBuffer;
};
} // namespace flr