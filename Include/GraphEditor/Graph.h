#pragma once

#include <glm/glm.hpp>
#include <imgui.h>

#include <vector>

namespace flr {
namespace GraphEditor {

struct NodeConnector;

struct NodeConnectionSlot {
  NodeConnector* m_connector;
  glm::vec2 m_pos;
};

class Node {
public:
  void draw(ImDrawList* drawList);
  void addInputSlot();
  void addOutputSlot();

  glm::vec2 getInputSlotPos(uint32_t slotIdx) const;
  glm::vec2 getOutputSlotPos(uint32_t slotIdx) const;

private:
  float m_slotRadius = 0.05f;
  float m_padding = 0.05f;

  glm::vec2 m_pos = glm::vec2(50.0f);
  glm::vec2 m_scale = glm::vec2(255.0f);
  // TODO: Fixed-size arrays would be better here
  std::vector<NodeConnectionSlot> m_inputSlots;
  std::vector<NodeConnectionSlot> m_outputSlots;
};

struct NodeConnector {
  Node* srcNode;
  uint32_t srcSlot;
  Node* dstNode;
  uint32_t dstSlot;
};

class Graph {
public:
  Graph();
  ~Graph();

  void draw();

private:
  std::vector<Node*> m_nodes;
  std::vector<NodeConnector> m_connectors;
};
} // namespace GraphEditor
} // namespace flr