#include "GraphEditor/Graph.h"

namespace flr {
namespace GraphEditor {
namespace {
struct SlotDrag {
  Node* m_node = nullptr;
  uint32_t m_slotIdx = 0;
  glm::vec2 m_pos{};
  bool m_bInputOrOutput = false;
  bool m_bActive = false;
};
static SlotDrag s_slotDrag{};
} // namespace

void Node::draw(ImDrawList* drawList) {
  ImGui::BeginGroup();
  ImGui::PushID(this);

  ImGuiIO& io = ImGui::GetIO();
  glm::vec2 wpos =
      m_pos + glm::vec2(ImGui::GetWindowPos().x, ImGui::GetWindowPos().y);

  drawList->AddRectFilled(
      ImVec2(wpos.x - m_padding * m_scale.x, wpos.y - m_padding * m_scale.y),
      ImVec2(
          wpos.x + (1.0f + m_padding) * m_scale.x,
          wpos.y + (1.0f + m_padding) * m_scale.y),
      ImColor(32, 32, 32, 255),
      m_padding * m_scale.x);
  drawList->AddRectFilled(
      ImVec2(wpos.x, wpos.y),
      ImVec2(wpos.x + m_scale.x, wpos.y + m_scale.y),
      ImColor(88, 88, 88, 255),
      m_padding * m_scale.x);

  ImGui::SetCursorPos(ImVec2(m_pos.x, m_pos.y));
  if (ImGui::Button("Add Input"))
    addInputSlot();
  ImGui::SameLine();
  if (ImGui::Button("Add Output"))
    addOutputSlot();

  for (uint32_t i = 0; i < m_inputSlots.size(); ++i) {
    const NodeConnectionSlot& slot = m_inputSlots[i];

    glm::vec2 slotPos = wpos + slot.m_pos * m_scale;
    glm::vec2 start = slotPos - m_scale * m_slotRadius;
    glm::vec2 end = slotPos + m_scale * m_slotRadius;

    drawList->AddRectFilled(
        ImVec2(start.x, start.y),
        ImVec2(end.x, end.y),
        ImColor(188, 24, 24, 255),
        m_scale.x * m_slotRadius);

    float r = m_slotRadius * m_scale.x * 2.0f;
    ImGui::SetCursorPos(ImVec2(
        m_pos.x + slot.m_pos.x * m_scale.x - r,
        m_pos.y + slot.m_pos.y * m_scale.y - r));
    ImGui::InvisibleButton(
        "slot",
        ImVec2(2.0f * r, 2.0f * r));

    if (ImGui::IsItemActive() && !s_slotDrag.m_bActive) {
      // start dragging this connector
      s_slotDrag.m_bActive = true;
      s_slotDrag.m_bInputOrOutput = true;
      s_slotDrag.m_node = this;
      s_slotDrag.m_slotIdx = i;
      s_slotDrag.m_pos = slotPos;
    }

    if (io.MouseReleased[0] && s_slotDrag.m_bActive) {
      // TODO: finalize drag connection
    }
  }

  for (uint32_t i = 0; i < m_outputSlots.size(); ++i) {
    const NodeConnectionSlot& slot = m_outputSlots[i];

    glm::vec2 slotPos = wpos + slot.m_pos * m_scale;
    glm::vec2 start = slotPos - m_scale * m_slotRadius;
    glm::vec2 end = slotPos + m_scale * m_slotRadius;

    drawList->AddRectFilled(
        ImVec2(start.x, start.y),
        ImVec2(end.x, end.y),
        ImColor(24, 188, 24, 255),
        m_scale.x * m_slotRadius);

    float r = m_slotRadius * m_scale.x * 2.0f;
    ImGui::SetCursorPos(ImVec2(
      m_pos.x + slot.m_pos.x * m_scale.x - r,
      m_pos.y + slot.m_pos.y * m_scale.y - r));
    ImGui::InvisibleButton(
      "slot",
      ImVec2(2.0f * r, 2.0f * r));

    if (ImGui::IsItemActive() && !s_slotDrag.m_bActive) {
      // start dragging this connector
      s_slotDrag.m_bActive = true;
      s_slotDrag.m_bInputOrOutput = false;
      s_slotDrag.m_node = this;
      s_slotDrag.m_slotIdx = i;
      s_slotDrag.m_pos = slotPos;
    }

    if (io.MouseReleased[0] && s_slotDrag.m_bActive) {
      // TODO: finalize drag connection
    }
  }

  ImGui::SetCursorPos(ImVec2(m_pos.x, m_pos.y));
  ImGui::InvisibleButton("node", ImVec2(m_scale.x, m_scale.y));

  if (ImGui::IsItemActive() && !s_slotDrag.m_bActive) {
    m_pos.x += io.MouseDelta.x;
    m_pos.y += io.MouseDelta.y;
  }
  ImGui::PopID();

  ImGui::EndGroup();
}

void Node::addInputSlot() {
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

void Node::addOutputSlot() {
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

glm::vec2 Node::getInputSlotPos(uint32_t slotIdx) const {
  glm::vec2 wpos =
      m_pos + glm::vec2(ImGui::GetWindowPos().x, ImGui::GetWindowPos().y);
  return wpos + m_inputSlots[slotIdx].m_pos * m_scale;
}

glm::vec2 Node::getOutputSlotPos(uint32_t slotIdx) const {
  glm::vec2 wpos =
      m_pos + glm::vec2(ImGui::GetWindowPos().x, ImGui::GetWindowPos().y);
  return wpos + m_outputSlots[slotIdx].m_pos * m_scale;
}

Graph::Graph() {}

Graph::~Graph() {
  for (Node* node : m_nodes) {
    delete node;
  }
}

void Graph::draw() {
  if (ImGui::Begin("GraphEditor")) {
    ImGuiIO& io = ImGui::GetIO();
    if (io.MouseReleased[0]) {
      // TODO: finalize drag

       s_slotDrag = {};
    }

    ImDrawList* drawlist = ImGui::GetWindowDrawList();

    if (s_slotDrag.m_bActive) {
      s_slotDrag.m_pos.x += io.MouseDelta.x;
      s_slotDrag.m_pos.y += io.MouseDelta.y;

      glm::vec2 slotPos =
          s_slotDrag.m_bInputOrOutput
              ? s_slotDrag.m_node->getInputSlotPos(s_slotDrag.m_slotIdx)
              : s_slotDrag.m_node->getOutputSlotPos(s_slotDrag.m_slotIdx);

      float offset = s_slotDrag.m_bInputOrOutput ? -250.0f : 250.0f;
      uint32_t col = s_slotDrag.m_bInputOrOutput ? 0xff3355ff : 0x55ff33ff;
      drawlist->AddBezierCubic(
          ImVec2(slotPos.x, slotPos.y),
          ImVec2(slotPos.x + offset, slotPos.y),
          ImVec2(s_slotDrag.m_pos.x - offset, s_slotDrag.m_pos.y),
          ImVec2(s_slotDrag.m_pos.x, s_slotDrag.m_pos.y),
          col,
          10.0f);
    }

    if (ImGui::Button("Add Node")) {
      m_nodes.push_back(new Node);
    }

    for (Node* node : m_nodes) {
      node->draw(drawlist);
    }
  }

  ImGui::End();
}

} // namespace GraphEditor
} // namespace flr