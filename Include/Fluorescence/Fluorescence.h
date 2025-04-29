#pragma once

#include "Project.h"
#include "Shared/CommonStructures.h"

#include <Althea/Allocator.h>
#include <Althea/CameraController.h>
#include <Althea/ComputePipeline.h>
#include <Althea/DeferredRendering.h>
#include <Althea/DescriptorSet.h>
#include <Althea/FrameBuffer.h>
#include <Althea/GlobalHeap.h>
#include <Althea/GlobalResources.h>
#include <Althea/GlobalUniforms.h>
#include <Althea/IGameInstance.h>
#include <Althea/Image.h>
#include <Althea/ImageBasedLighting.h>
#include <Althea/ImageResource.h>
#include <Althea/ImageView.h>
#include <Althea/Model.h>
#include <Althea/PerFrameResources.h>
#include <Althea/PointLight.h>
#include <Althea/RenderPass.h>
#include <Althea/Sampler.h>
#include <Althea/ScreenSpaceReflection.h>
#include <Althea/StructuredBuffer.h>
#include <Althea/Texture.h>
#include <Althea/TransientUniforms.h>
#include <glm/glm.hpp>

#include <vector>

using namespace AltheaEngine;

namespace AltheaEngine {
class Application;
} // namespace AltheaEngine

namespace flr {
extern Application* GApplication;
extern GlobalHeap* GGlobalHeap;

struct FlrAppOptions {
  bool bStandaloneMode = true;
};

class IFlrProgram {
public:
  virtual void setupDescriptorTable(DescriptorSetLayoutBuilder& builder) {}
  virtual void createDescriptors(ResourcesAssignment& assignment) {}
  virtual void createRenderState(Project* project, SingleTimeCommandBuffer& commandBuffer) {}
  virtual void destroyRenderState() {}

  virtual void tick(Project* project, const FrameContext& frame) {};
  virtual void draw(Project* project, VkCommandBuffer commandBuffer, const FrameContext& frame) {};
};

class Fluorescence : public IGameInstance {
public:
  Fluorescence(const FlrAppOptions& options = {});
  // virtual ~Fluorescence();

  void setStartupProject(const char* path);

  template <typename T, class... TArgs>
  T* registerProgram(TArgs&&... args) {
    m_programs.push_back(std::make_unique<T>(std::forward<TArgs>(args)...));
    return (T*)m_programs.back().get();
  }

  void initGame(Application& app) override;
  void shutdownGame(Application& app) override;

  void createRenderState(Application& app) override;
  void destroyRenderState(Application& app) override;

  void tick(Application& app, const FrameContext& frame) override;
  void draw(
      Application& app,
      VkCommandBuffer commandBuffer,
      const FrameContext& frame) override;

private:
  void _createGlobalResources(
      Application& app,
      SingleTimeCommandBuffer& commandBuffer);
  GlobalHeap m_heap;
  TransientUniforms<FlrUniforms> m_uniforms;
  PerFrameResources m_descriptorSets;

  void _createDisplayPass(Application& app);
  RenderPass m_displayPass;
  SwapChainFrameBufferCollection m_swapChainFrameBuffers;

  FlrAppOptions m_options;
  std::vector<std::unique_ptr<IFlrProgram>> m_programs;

  Project* m_pProject = nullptr;
  bool m_bOpenFileDialogue = false;
  bool m_bReloadProject = false;
  bool m_bPaused = false;
  bool m_bFreezeTime = false;
  float m_time = 0.0f;
};
} // namespace flr
