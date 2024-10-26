#include "Fluorescence.h"

#include <Althea/Application.h>
#include <Althea/Camera.h>
#include <Althea/Cubemap.h>
#include <Althea/DefaultTextures.h>
#include <Althea/DescriptorSet.h>
#include <Althea/GraphicsPipeline.h>
#include <Althea/Gui.h>
#include <Althea/InputManager.h>
#include <Althea/ModelViewProjection.h>
#include <Althea/Primitive.h>
#include <Althea/SingleTimeCommandBuffer.h>
#include <Althea/Skybox.h>
#include <Althea/Utilities.h>
#include <glm/glm.hpp>
#include <glm/gtc/constants.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <vulkan/vulkan.h>

#include <array>
#include <cstdint>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

using namespace AltheaEngine;

namespace flr {

Fluorescence::Fluorescence() {}

void Fluorescence::initGame(Application& app) {
  // TODO: need to unbind these at shutdown
  InputManager& input = app.getInputManager();
  input.setMouseCursorHidden(false);

  // Recreate any stale pipelines (shader hot-reload)
  input.addKeyBinding(
      {GLFW_KEY_R, GLFW_PRESS, GLFW_MOD_CONTROL},
      [&app, this]() { m_displayPass.tryRecompile(app); });
}

void Fluorescence::shutdownGame(Application& app) {}

void Fluorescence::createRenderState(Application& app) {
  Gui::createRenderState(app);

  SingleTimeCommandBuffer commandBuffer(app);
  _createGlobalResources(app, commandBuffer);
  _createDisplayPass(app);
}

void Fluorescence::destroyRenderState(Application& app) {
  Gui::destroyRenderState(app);

  m_displayPass = {};
  m_swapChainFrameBuffers = {};

  m_uniforms = {};
  m_heap = {};
}

namespace {
struct NodeConnector;
// TODO: move this to a dedicated layout manager class...
// this is just some quick prototyping...
struct NodeConnectionSlot {
  NodeConnector* m_connector;
  glm::vec2 m_pos;
};
struct NodeLayout {
  float m_slotRadius = 0.05f;
  float m_padding = 0.05f;

  glm::vec2 m_pos = glm::vec2(50.0f);
  glm::vec2 m_scale = glm::vec2(255.0f);
  // TODO: Fixed-size arrays would be better here
  std::vector<NodeConnectionSlot> m_inputSlots;
  std::vector<NodeConnectionSlot> m_outputSlots;

  void draw(ImDrawList* drawList) {
    ImGuiIO& io = ImGui::GetIO();
    glm::vec2 wpos =
        m_pos + glm::vec2(ImGui::GetWindowPos().x, ImGui::GetWindowPos().y);

    drawList->AddRectFilled(
        ImVec2(wpos.x, wpos.y),
        ImVec2(wpos.x + m_scale.x, wpos.y + m_scale.y),
        ImColor(88, 88, 88, 255),
        m_padding * m_scale.x);
    
    for (const NodeConnectionSlot& slot : m_inputSlots) {
      glm::vec2 slotPos = wpos + slot.m_pos * m_scale;
      glm::vec2 start = slotPos - m_scale * m_slotRadius;
      glm::vec2 end = slotPos + m_scale * m_slotRadius;

      drawList->AddRectFilled(
          ImVec2(start.x, start.y),
          ImVec2(end.x, end.y),
          ImColor(188, 24, 24, 255),
          m_scale.x * m_slotRadius);
    }

    for (const NodeConnectionSlot& slot : m_outputSlots) {
      glm::vec2 slotPos = wpos + slot.m_pos * m_scale;
      glm::vec2 start = slotPos - m_scale * m_slotRadius;
      glm::vec2 end = slotPos + m_scale * m_slotRadius;

      drawList->AddRectFilled(
          ImVec2(start.x, start.y),
          ImVec2(end.x, end.y),
          ImColor(24, 188, 24, 255),
          m_scale.x * m_slotRadius);
    }

    ImGui::SetCursorPos(ImVec2(m_pos.x, m_pos.y));
    ImGui::InvisibleButton("node", ImVec2(m_scale.x, m_scale.y));
    if (ImGui::IsItemActive()) {
      m_pos.x += io.MouseDelta.x;
      m_pos.y += io.MouseDelta.y;
    }
  }

  void addInputSlot() {
    {
      NodeConnectionSlot& slot = m_inputSlots.emplace_back();
      slot.m_connector = nullptr;
    }

    float spacing = (1.0f - 2.0f * m_padding) / m_inputSlots.size();
    glm::vec2 pos(m_padding, m_padding + 0.5f * spacing);
    for (NodeConnectionSlot& slot : m_inputSlots) {
      slot.m_pos = pos;
      pos.y += spacing;
    }
  }

  void addOutputSlot() {
    {
      NodeConnectionSlot& slot = m_outputSlots.emplace_back();
      slot.m_connector = nullptr;
    }

    float spacing = (1.0f - 2.0f * m_padding) / m_outputSlots.size();
    glm::vec2 pos(1.0f - m_padding, m_padding + 0.5f * spacing);
    for (NodeConnectionSlot& slot : m_outputSlots) {
      slot.m_pos = pos;
      pos.y += spacing;
    }
  }
};
struct NodeConnector {
  NodeLayout* srcNode;
  uint32_t srcSlot;
  NodeLayout* dstNode;
  uint32_t dstSlot;
};
} // namespace
void Fluorescence::tick(Application& app, const FrameContext& frame) {
  {
    Gui::startRecordingImgui();

    const ImGuiViewport* main_viewport = ImGui::GetMainViewport();
    if (ImGui::BeginMainMenuBar()) {
      static bool s_bSelectedFileTab = false;
      if (ImGui::MenuItem("File", "TEST", &s_bSelectedFileTab)) {
      }
    }

    ImGui::EndMainMenuBar();

    // TODO: move this somewhere else
    static NodeLayout node{};

    static bool s_bShowGraphEditor = true;

    if (s_bShowGraphEditor) {
      const ImGuiViewport* main_viewport = ImGui::GetMainViewport();

      if (ImGui::Begin("GraphEditor")) {
        if (ImGui::Button("Add Input"))
          node.addInputSlot();
        ImGui::SameLine();
        if (ImGui::Button("Add Output"))
          node.addOutputSlot();
        
        ImGui::BeginGroup();
        ImDrawList* drawList = ImGui::GetWindowDrawList();
        node.draw(drawList);
        ImGui::EndGroup();
      }

      ImGui::End();
    }

    Gui::finishRecordingImgui();
  }

  InputManager::MousePos mpos = app.getInputManager().getCurrentMousePos();
  uint32_t inputMask = app.getInputManager().getCurrentInputMask();

  static uint32_t frameCount = 0;
  static uint32_t prevInputMask = inputMask;

  FlrUniforms uniforms;
  uniforms.mouseUv.x = static_cast<float>(mpos.x);
  uniforms.mouseUv.y = static_cast<float>(mpos.y);
  uniforms.time = static_cast<float>(frame.currentTime);
  uniforms.frameCount = frameCount++;
  uniforms.prevInputMask = prevInputMask;
  uniforms.inputMask = inputMask;

  m_uniforms.getCurrentUniformBuffer(frame).updateUniforms(uniforms);
}

void Fluorescence::_createGlobalResources(
    Application& app,
    SingleTimeCommandBuffer& commandBuffer) {
  m_heap = GlobalHeap(app);
  AltheaEngine::registerDefaultTexturesToHeap(m_heap);
  m_uniforms = TransientUniforms<FlrUniforms>(app, {});
  m_uniforms.registerToHeap(m_heap);
}
void Fluorescence::_createDisplayPass(Application& app) {
  VkClearValue colorClear;
  colorClear.color = {{0.0f, 0.0f, 0.0f, 1.0f}};
  VkClearValue depthClear;
  depthClear.depthStencil = {1.0f, 0};

  std::vector<Attachment> attachments = {Attachment{
      ATTACHMENT_FLAG_COLOR,
      app.getSwapChainImageFormat(),
      colorClear,
      false, // forPresent is false since the imGUI pass follows the
             // deferred pass
      false,
      true}};

  std::vector<SubpassBuilder> subpassBuilders;

  // DEFERRED PBR PASS
  {
    SubpassBuilder& subpassBuilder = subpassBuilders.emplace_back();
    subpassBuilder.colorAttachments.push_back(0);

    ShaderDefines defs;

    subpassBuilder.pipelineBuilder.setCullMode(VK_CULL_MODE_FRONT_BIT)
        .setDepthTesting(false);
    {
      ShaderDefines defs;
      defs.emplace("IS_VERTEX_SHADER", "");
      defs.emplace("VS_FullScreen", "main");
      subpassBuilder.pipelineBuilder.addVertexShader(
          GProjectDirectory + "/Shaders/Display.glsl",
          defs);
    }

    {
      ShaderDefines defs;
      defs.emplace("IS_PIXEL_SHADER", "");
      defs.emplace("PS_Default", "main");
      subpassBuilder.pipelineBuilder.addFragmentShader(
          GProjectDirectory + "/Shaders/Display.glsl",
          defs);
    }

    subpassBuilder.pipelineBuilder.layoutBuilder
        .addDescriptorSet(m_heap.getDescriptorSetLayout())
        .addPushConstants<FlrPush>(VK_SHADER_STAGE_ALL);
  }

  m_displayPass = RenderPass(
      app,
      app.getSwapChainExtent(),
      std::move(attachments),
      std::move(subpassBuilders));

  m_swapChainFrameBuffers =
      SwapChainFrameBufferCollection(app, m_displayPass, {});
}

void Fluorescence::draw(
    Application& app,
    VkCommandBuffer commandBuffer,
    const FrameContext& frame) {

  VkDescriptorSet heapDescriptorSet = m_heap.getDescriptorSet();

  {
    FlrPush push{};

    ActiveRenderPass pass = m_displayPass.begin(
        app,
        commandBuffer,
        frame,
        m_swapChainFrameBuffers.getCurrentFrameBuffer(frame));
    // Bind global descriptor sets
    pass.setGlobalDescriptorSets(gsl::span(&heapDescriptorSet, 1));
    pass.getDrawContext().updatePushConstants(push, 0);

    {
      const DrawContext& context = pass.getDrawContext();
      context.bindDescriptorSets();
      context.draw(3);
    }
  }

  Gui::draw(app, frame, commandBuffer);
}
} // namespace flr