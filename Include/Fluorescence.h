#pragma once

#include "Shared/CommonStructures.h"
#include "Project.h"

#include <Althea/Allocator.h>
#include <Althea/CameraController.h>
#include <Althea/ComputePipeline.h>
#include <Althea/DeferredRendering.h>
#include <Althea/DescriptorSet.h>
#include <Althea/FrameBuffer.h>
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
#include <Althea/GlobalHeap.h>
#include <Althea/GlobalUniforms.h>
#include <Althea/GlobalResources.h>
#include <glm/glm.hpp>

#include <vector>

using namespace AltheaEngine;

namespace AltheaEngine {
class Application;
} // namespace AltheaEngine

namespace flr {

class Fluorescence : public IGameInstance {
public:
  Fluorescence();
  // virtual ~Fluorescence();

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

  void _createDisplayPass(Application& app);
  RenderPass m_displayPass;
  SwapChainFrameBufferCollection m_swapChainFrameBuffers;

  Project* m_pProject = nullptr;
};
} // namespace flr
