#include "GraphEditor/Graph.h"

namespace flr {
namespace GraphEditor {
namespace {

#define SHOW_INVISIBLE_BUTTONS 0
#if SHOW_INVISIBLE_BUTTONS
#define InvisibleButton Button
#endif

struct SlotDrag {
  Node* m_srcNode = nullptr;
  uint32_t m_srcSlot = 0;
  Node* m_dstNode = nullptr;
  uint32_t m_dstSlot = 0;

  glm::vec2 m_pos{};
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
  if (ImGui::Button("+ Input"))
    addInputSlot();
  ImGui::SameLine();
  if (ImGui::Button("+ Output"))
    addOutputSlot();

  for (uint32_t i = 0; i < m_inputSlots.size(); ++i) {
    ImGui::PushID(i);
    const NodeConnectionSlot& slot = m_inputSlots[i];

    glm::vec2 slotPos = wpos + slot.m_pos * m_scale;
    glm::vec2 start = slotPos - m_scale * m_slotRadius;
    glm::vec2 end = slotPos + m_scale * m_slotRadius;

    drawList->AddCircleFilled(
        ImVec2(slotPos.x, slotPos.y),
        m_scale.x * (m_slotRadius + 0.5f * m_padding),
        ImColor(12, 12, 12, 255));
    drawList->AddCircleFilled(
        ImVec2(slotPos.x, slotPos.y),
        m_scale.x * m_slotRadius,
        ImColor(188, 24, 24, 255));

    float r = m_slotRadius * m_scale.x * 4.0f;
    ImGui::SetCursorPos(ImVec2(
        m_pos.x + slot.m_pos.x * m_scale.x - r,
        m_pos.y + slot.m_pos.y * m_scale.y - r));
    ImGui::InvisibleButton("inputSlot", ImVec2(2.0f * r, 2.0f * r));

    if (ImGui::IsItemActive() && !s_slotDrag.m_bActive) {
      // start dragging this connector
      s_slotDrag.m_bActive = true;
      s_slotDrag.m_srcNode = nullptr;
      s_slotDrag.m_srcSlot = 0;
      s_slotDrag.m_dstNode = this;
      s_slotDrag.m_dstSlot = i;
      s_slotDrag.m_pos = slotPos;
    }

    bool bHovering = ImGui::IsMouseHoveringRect(
        ImGui::GetItemRectMin(),
        ImGui::GetItemRectMax());
    if (bHovering && io.MouseReleased[0] && s_slotDrag.m_bActive &&
        s_slotDrag.m_srcNode) {
      // finalize drag connection
      s_slotDrag.m_dstNode = this;
      s_slotDrag.m_dstSlot = i;
    }
    ImGui::PopID();
  }

  for (uint32_t i = 0; i < m_outputSlots.size(); ++i) {
    ImGui::PushID(i);
    const NodeConnectionSlot& slot = m_outputSlots[i];

    glm::vec2 slotPos = wpos + slot.m_pos * m_scale;
    glm::vec2 start = slotPos - m_scale * m_slotRadius;
    glm::vec2 end = slotPos + m_scale * m_slotRadius;

    drawList->AddCircleFilled(
        ImVec2(slotPos.x, slotPos.y),
        m_scale.x * (m_slotRadius + 0.5f * m_padding),
        ImColor(12, 12, 12, 255));
    drawList->AddCircleFilled(
        ImVec2(slotPos.x, slotPos.y),
        m_scale.x * m_slotRadius,
        ImColor(25, 188, 24, 255));

    float r = m_slotRadius * m_scale.x * 4.0f;
    ImGui::SetCursorPos(ImVec2(
        m_pos.x + slot.m_pos.x * m_scale.x - r,
        m_pos.y + slot.m_pos.y * m_scale.y - r));
    ImGui::InvisibleButton("outputslot", ImVec2(2.0f * r, 2.0f * r));

    if (ImGui::IsItemActive() && !s_slotDrag.m_bActive) {
      // start dragging this connector
      s_slotDrag.m_bActive = true;
      s_slotDrag.m_srcNode = this;
      s_slotDrag.m_srcSlot = i;
      s_slotDrag.m_dstNode = nullptr;
      s_slotDrag.m_dstSlot = 0;
      s_slotDrag.m_pos = slotPos;
    }

    bool bHovering = ImGui::IsMouseHoveringRect(
        ImGui::GetItemRectMin(),
        ImGui::GetItemRectMax());
    if (bHovering && io.MouseReleased[0] && s_slotDrag.m_bActive &&
        s_slotDrag.m_dstNode) {
      // finalize drag connection
      s_slotDrag.m_srcNode = this;
      s_slotDrag.m_srcSlot = i;
    }
    ImGui::PopID();
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

void Node::clearInput(uint32_t slotIdx) {
  NodeConnectionSlot& slot = m_inputSlots[slotIdx];
  if (slot.m_otherNode) {
    slot.m_otherNode->m_outputSlots[slot.m_otherNodeSlotIdx].m_otherNode =
        nullptr;
    slot.m_otherNode->m_outputSlots[slot.m_otherNodeSlotIdx]
        .m_otherNodeSlotIdx = 0;
  }

  slot.m_otherNode = nullptr;
  slot.m_otherNodeSlotIdx = 0;
}

void Node::clearOutput(uint32_t slotIdx) {
  NodeConnectionSlot& slot = m_outputSlots[slotIdx];
  if (slot.m_otherNode) {
    slot.m_otherNode->m_inputSlots[slot.m_otherNodeSlotIdx].m_otherNode =
        nullptr;
    slot.m_otherNode->m_inputSlots[slot.m_otherNodeSlotIdx].m_otherNodeSlotIdx =
        0;
  }

  slot.m_otherNode = nullptr;
  slot.m_otherNodeSlotIdx = 0;
}

void Node::addInputSlot() {
  {
    NodeConnectionSlot& slot = m_inputSlots.emplace_back();
    slot.m_otherNode = nullptr;
    slot.m_otherNodeSlotIdx = 0;
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
    slot.m_otherNode = nullptr;
    slot.m_otherNodeSlotIdx = 0;
  }

  float spacing = (1.0f - 2.0f * m_padding) / m_outputSlots.size();
  glm::vec2 pos(1.0f - m_padding, m_padding + 0.5f * spacing);
  for (NodeConnectionSlot& slot : m_outputSlots) {
    slot.m_pos = pos;
    pos.y += spacing;
  }
}

/*static*/
void Node::connect(Node* src, uint32_t srcSlot, Node* dst, uint32_t dstSlot) {
  src->m_outputSlots[srcSlot].m_otherNode = dst;
  src->m_outputSlots[srcSlot].m_otherNodeSlotIdx = dstSlot;
  dst->m_inputSlots[dstSlot].m_otherNode = src;
  dst->m_inputSlots[dstSlot].m_otherNodeSlotIdx = srcSlot;
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
    //ImGui::SetWindowFontScale(0.5f);
    ImGuiIO& io = ImGui::GetIO();

    ImDrawList* drawlist = ImGui::GetWindowDrawList();
    if (ImGui::Button("Add Node")) {
      m_nodes.push_back(new Node);
    }

    for (Node* node : m_nodes) {
      node->draw(drawlist);
    }

    for (const Node* n : m_nodes) {
      for (int i = 0; i < n->m_outputSlots.size(); i++) {
        const NodeConnectionSlot& s = n->m_outputSlots[i];
        if (!s.m_otherNode)
          continue;

        glm::vec2 p0 = n->getOutputSlotPos(i);
        glm::vec2 p3 = s.m_otherNode->getInputSlotPos(s.m_otherNodeSlotIdx);

        float offset = 250.0f;
        uint32_t col = 0xff3355ff;
        drawlist->AddBezierCubic(
            ImVec2(p0.x, p0.y),
            ImVec2(p0.x + offset, p0.y),
            ImVec2(p3.x - offset, p3.y),
            ImVec2(p3.x, p3.y),
            ImColor(18, 18, 18, 255),
            15.0f);
        drawlist->AddBezierCubic(
            ImVec2(p0.x, p0.y),
            ImVec2(p0.x + offset, p0.y),
            ImVec2(p3.x - offset, p3.y),
            ImVec2(p3.x, p3.y),
            col,
            6.0f);
      }
    }

    if (io.MouseReleased[0]) {
      if (s_slotDrag.m_srcNode && s_slotDrag.m_dstNode &&
          s_slotDrag.m_srcNode != s_slotDrag.m_dstNode) {
        s_slotDrag.m_srcNode->clearOutput(s_slotDrag.m_srcSlot);
        s_slotDrag.m_dstNode->clearInput(s_slotDrag.m_dstSlot);
        Node::connect(
            s_slotDrag.m_srcNode,
            s_slotDrag.m_srcSlot,
            s_slotDrag.m_dstNode,
            s_slotDrag.m_dstSlot);
      }

      s_slotDrag = {};
    }
    if (s_slotDrag.m_bActive) {
      s_slotDrag.m_pos.x += io.MouseDelta.x;
      s_slotDrag.m_pos.y += io.MouseDelta.y;

      glm::vec2 slotPos =
          s_slotDrag.m_srcNode
              ? s_slotDrag.m_srcNode->getOutputSlotPos(s_slotDrag.m_srcSlot)
              : s_slotDrag.m_dstNode->getInputSlotPos(s_slotDrag.m_dstSlot);

      float offset = s_slotDrag.m_srcNode ? 250.0f : -250.0f;
      uint32_t col = s_slotDrag.m_srcNode ? 0xff3355ff : 0x55ff33ff;
      drawlist->AddBezierCubic(
          ImVec2(slotPos.x, slotPos.y),
          ImVec2(slotPos.x + offset, slotPos.y),
          ImVec2(s_slotDrag.m_pos.x - offset, s_slotDrag.m_pos.y),
          ImVec2(s_slotDrag.m_pos.x, s_slotDrag.m_pos.y),
          ImColor(18, 18, 18, 255),
          15.0f);
      drawlist->AddBezierCubic(
          ImVec2(slotPos.x, slotPos.y),
          ImVec2(slotPos.x + offset, slotPos.y),
          ImVec2(s_slotDrag.m_pos.x - offset, s_slotDrag.m_pos.y),
          ImVec2(s_slotDrag.m_pos.x, s_slotDrag.m_pos.y),
          col,
          6.0f);
    }
  }

  ImGui::End();
}

} // namespace GraphEditor
} // namespace flr