#pragma once

#include "ParsedFlr.h"
#include "Shared/CommonStructures.h"
#include "SimpleObjLoader.h"

#include <Althea/BindlessHandle.h>
#include <Althea/BufferUtilities.h>
#include <Althea/ComputePipeline.h>
#include <Althea/FrameContext.h>
#include <Althea/Framebuffer.h>
#include <Althea/ImageResource.h>
#include <Althea/PerFrameResources.h>
#include <Althea/RenderPass.h>
#include <Althea/StructuredBuffer.h>
#include <Althea/TransientUniforms.h>
#include <Althea/Utilities.h>
#include <vulkan/vulkan.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

using namespace AltheaEngine;

namespace flr {
class Audio;

struct TaskBlockId {
  TaskBlockId() : idx(~0u) {}
  TaskBlockId(uint32_t i) : idx(i) {}
  bool isValid() const { return idx != ~0u; }
  uint32_t idx;
};

class Project {
public:
  Project(
      SingleTimeCommandBuffer& commandBuffer,
      const TransientUniforms<FlrUniforms>& flrUniforms,
      const char* projectPath);
  ~Project();

  void tick(const FrameContext& frame);

  void draw(VkCommandBuffer commandBuffer, const FrameContext& frame);

  TextureHandle getOutputTexture() const {
    return m_images[m_parsed.m_displayImageIdx].textureHandle;
  }

  bool isReady() const { return !hasFailed() && !hasRecompileFailed(); }

  bool hasFailed() const { return m_parsed.m_failed; }

  const char* getErrorMessage() const { return m_parsed.m_errMsg; }

  bool hasRecompileFailed() const { return m_failedShaderCompile; }

  const char* getShaderCompileErrors() const { return m_shaderCompileErrMsg; }

  void tryRecompile();

  TaskBlockId findTaskBlock(const char* name) const;
  void executeTaskBlock(TaskBlockId id, VkCommandBuffer commandBuffer, const FrameContext& frame);

  std::optional<bool> getCheckBoxValue(const char* name) const;
  std::optional<float> getSliderFloatValue(const char* name) const;
  std::optional<uint32_t> getSliderUintValue(const char* name) const;
  std::optional<int> getSliderIntValue(const char* name) const;
  std::optional<glm::vec4> getColorPickerValue(const char* name) const;

  BufferAllocation* getBufferByName(const char* name);

  void setPushConstants(uint32_t push0, uint32_t push1 = 0, uint32_t push2 = 0, uint32 push3 = 0);

private:
  void executeTaskList(const std::vector<ParsedFlr::Task>& tasks, VkCommandBuffer commandBuffer, const FrameContext& frame);

  ParsedFlr m_parsed;

  std::vector<BufferAllocation> m_buffers;
  std::vector<ImageResource> m_images;
  std::vector<ImageResource> m_textureFiles;
  std::vector<ComputePipeline> m_computePipelines;

  struct DrawTask {
    uint32_t renderpassIdx;
    uint32_t subpassIdx;
    uint32_t vertexCount;
    uint32_t instanceCount;
  };

  struct DrawPass {
    RenderPass m_renderPass;
    FrameBuffer m_frameBuffer;
  };
  std::vector<DrawPass> m_drawPasses;

  PerFrameResources m_descriptorSets;
  DynamicBuffer m_dynamicUniforms;
  std::vector<std::byte> m_dynamicDataBuffer;

  CameraController m_cameraController;
  PerspectiveCamera m_cameraArgs;
  TransientUniforms<PerspectiveCamera> m_perspectiveCamera;
  TransientUniforms<AudioInput> m_audioInput;

  std::vector<SimpleObjLoader::LoadedObj> m_objModels;

  std::unique_ptr<Audio> m_pAudio;

  struct PendingSaveImage {
    std::string m_saveFileName;
    uint32_t imageIdx;
  };
  std::optional<PendingSaveImage> m_pendingSaveImage;

  struct GenericPush {
    uint32_t push0;
    uint32_t push1;
    uint32_t push2;
    uint32_t push3;
  };
  GenericPush m_pushData;
  
  bool m_bHasDynamicData;

  bool m_failedShaderCompile;
  char m_shaderCompileErrMsg[2048];
};
} // namespace flr