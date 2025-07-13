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

struct GenericId {
  GenericId() : idx(~0u) {}
  GenericId(uint32_t i) : idx(i) {}
  bool isValid() const { return idx != ~0u; }
  uint32_t idx;
};

#define CREATE_ID_TYPE(NAME)              \
struct NAME : GenericId {                 \
  NAME() : GenericId() {}                 \
  NAME(uint32_t idx) : GenericId(idx) {}  \
};

CREATE_ID_TYPE(TaskBlockId);
CREATE_ID_TYPE(ComputeShaderId);
CREATE_ID_TYPE(BufferId);

template <typename T>
struct FlrUiView {
  friend class Project;
public:
  FlrUiView() : m_ptr(nullptr) {}
  FlrUiView(const FlrUiView<T>& other) : m_ptr(other.m_ptr) {}

  T& operator->() { return *m_ptr; }
  T& operator*() { return *m_ptr; }
  operator bool() const { return m_ptr != nullptr; }
private:
  FlrUiView(T* ptr) : m_ptr(ptr) {}
  T* m_ptr;
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

  ComputeShaderId findComputeShader(const char* name) const;
  void dispatch(ComputeShaderId compShader, uint32_t groupCountX, uint32_t groupCountY, uint32_t groupCountZ, VkCommandBuffer commandBuffer, const FrameContext& frame) const;
  void dispatchThreads(ComputeShaderId compShader, uint32_t threadCountX, uint32_t threadCountY, uint32_t threadCountZ, VkCommandBuffer commandBuffer, const FrameContext& frame) const;

  FlrUiView<bool> getCheckBox(const char* name) const;
  FlrUiView<float> getSliderFloat(const char* name) const;
  FlrUiView<uint32_t> getSliderUint(const char* name) const;
  FlrUiView<int> getSliderInt(const char* name) const;
  FlrUiView<glm::vec4> getColorPicker(const char* name) const;

  std::optional<float> getConstFloat(const char* name) const;
  std::optional<uint32_t> getConstUint(const char* name) const;
  std::optional<int> getConstInt(const char* name) const;

  BufferId findBuffer(const char* name) const;
  BufferAllocation* getBufferAlloc(BufferId buf, uint32_t subBufIdx);
  uint32_t getSubBufferCount(BufferId buf) const;
  void barrierRW(BufferId buf, VkCommandBuffer commandBuffer) const;

  void setPushConstants(uint32_t push0, uint32_t push1 = 0, uint32_t push2 = 0, uint32 push3 = 0);

private:

  template <typename TValue, typename TUi>
  static FlrUiView<TValue> getUiElemByName(const char* name, const std::vector<TUi>& elems) {
    if (auto pElem = getElemByName(name, elems))
      return FlrUiView<TValue>(reinterpret_cast<TValue*>(pElem->pValue));
    return FlrUiView<TValue>();
  }

  void executeTaskList(const std::vector<ParsedFlr::Task>& tasks, VkCommandBuffer commandBuffer, const FrameContext& frame);

  ParsedFlr m_parsed;

  std::vector<std::vector<BufferAllocation>> m_buffers;
  std::vector<VkAccessFlags> m_bufferResourceStates;
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

  struct PendingSaveBuffer {
    std::string m_saveFileName;
    uint32_t bufferIdx;
  };
  std::optional<PendingSaveBuffer> m_pendingSaveBuffer;

  std::vector<uint32_t> m_pendingTaskBlockExecs;

  struct GenericPush {
    uint32_t push0;
    uint32_t push1;
    uint32_t push2;
    uint32_t push3;
  };
  GenericPush m_pushData;

  bool m_bHasDynamicData;
  bool m_bFirstDraw;

  bool m_failedShaderCompile;
  char m_shaderCompileErrMsg[2048];
};
} // namespace flr