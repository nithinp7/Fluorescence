#pragma once

#include <glm/glm.hpp>
#include <imgui.h>

#include <vector>

namespace flr {
namespace GraphEditor {

class Node;
struct NodeConnector;

struct NodeConnectionSlot {
  Node* m_otherNode;
  uint32_t m_otherNodeSlotIdx;
  glm::vec2 m_pos;
};

class Node {
  friend class Graph;

public:
  void draw(ImDrawList* drawList);
  void clearInput(uint32_t slotIdx);
  void clearOutput(uint32_t slotIdx);
  void addInputSlot();
  void addOutputSlot();

  static void connect(Node* src, uint32_t srcSlot, Node* dst, uint32_t dstSlot);

  glm::vec2 getInputSlotPos(uint32_t slotIdx) const;
  glm::vec2 getOutputSlotPos(uint32_t slotIdx) const;

private:
  float m_slotRadius = 0.025f;
  float m_padding = 0.05f;

  glm::vec2 m_pos = glm::vec2(50.0f);
  glm::vec2 m_scale = glm::vec2(255.0f);
  // TODO: Fixed-size arrays would be better here
  std::vector<NodeConnectionSlot> m_inputSlots;
  std::vector<NodeConnectionSlot> m_outputSlots;
};

class Graph {
public:
  Graph();
  ~Graph();

  void draw();

private:
  std::vector<Node*> m_nodes;
};
} // namespace GraphEditor
} // namespace flr