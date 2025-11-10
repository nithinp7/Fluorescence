#pragma once
#include "IpcProgram.h"

#include <stdio.h>
#include <tchar.h>

#include <iostream>
#include <optional>

// ??
#pragma comment(lib, "user32.lib")

namespace flr {
namespace flr_cmds {
namespace {
class CmdStreamView {
public:
  CmdStreamView(char* stream, size_t streamSize)
      : m_pStream(stream),
        m_streamOffset(0),
        m_streamSize(streamSize),
        m_bFailed(!m_pStream || (m_streamSize == 0)) {}

  template <typename T> std::optional<T> read() {
    if (isFailed())
      return std::nullopt;

    size_t sz = sizeof(T);
    if ((m_streamOffset + sz) > m_streamSize) {
      m_bFailed = true;
      return std::nullopt;
    }

    T val;
    memcpy(&val, m_pStream + m_streamOffset, sz);
    m_streamOffset += sz;
    return val;
  }

  void setFailed() { m_bFailed = true; }
  bool isFailed() const { return m_bFailed; }

  void copyTo(void* dst, size_t srcOffset, size_t sizeBytes) {
    if (m_bFailed)
      return;
    if (srcOffset > m_streamSize || (srcOffset + sizeBytes) > m_streamSize) {
      m_bFailed = true;
      return;
    }
    memcpy(dst, m_pStream + srcOffset, sizeBytes);
  }
private:
  char* m_pStream;
  size_t m_streamOffset;
  size_t m_streamSize;
  bool m_bFailed;
};
} // namespace

bool processCmdList(
    Project* project,
    VkCommandBuffer commandBuffer,
    const FrameContext& frame,
    char* stream,
    size_t streamSize) {
  CmdStreamView streamView(stream, streamSize);

  while (auto cmdType = streamView.read<uint32_t>()) {
    switch (*cmdType) {
    case CMD_FINISH: {
      return true; // denotes end of cmdlist
    }
    case CMD_PUSH_CONSTANTS: {
      if (auto cmd = streamView.read<CmdPushConstants>()) {
        project
            ->setPushConstants(cmd->push0, cmd->push1, cmd->push2, cmd->push3);
      }
      break;
    }
    case CMD_DISPATCH: {
      if (auto cmd = streamView.read<CmdDispatch>()) {
        project->dispatch(
            ComputeShaderId(cmd->computeShaderId),
            cmd->groupCountX,
            cmd->groupCountY,
            cmd->groupCountZ,
            commandBuffer,
            frame);
      }
      break;
    }
    case CMD_BARRIER_RW: {
      if (auto cmd = streamView.read<CmdBarrierRW>()) {
        project->barrierRW(BufferId(cmd->bufferId), commandBuffer);
      }
      break;
    }
    case CMD_BUFFER_WRITE: {
      if (auto cmd = streamView.read<CmdBufferWrite>()) {
        if (cmd->subBufIdx == ~0u)
          cmd->subBufIdx = frame.frameRingBufferIndex;
        BufferAllocation* alloc = project->getBufferAlloc(BufferId(cmd->bufferId), cmd->subBufIdx);
        char* pMapped = (char*)alloc->mapMemory();
        streamView.copyTo(pMapped + cmd->dstOffset, cmd->srcOffset, cmd->sizeBytes);
        alloc->unmapMemory();
      }
      break;
    }
    case CMD_UNIFORM_WRITE: {
      if (auto cmd = streamView.read<CmdUniformWrite>()) {
        if (cmd->dstOffset + cmd->sizeBytes > project->getDynamicDataSize())
          streamView.setFailed();
        streamView.copyTo(project->getDynamicDataPtr() + cmd->dstOffset, cmd->srcOffset, cmd->sizeBytes);
      }
      break;
    }
    case CMD_RUN_TASK: {
      if (auto cmd = streamView.read<CmdRunTask>()) {
        project->executeTaskBlock(TaskBlockId(cmd->taskId), commandBuffer, frame);
      }
      break;
    }
    default: {
      return false;
    }
    }
  }

  return false;
}
} // namespace flr_cmds

namespace flr_handshake {

// the establishment is a flr --> script communication format consisting
// of mappings between string names and element IDs
void establishProject(Project* project, char* outStream, size_t streamSize) {
  char* pDynamicData = (char*)project->getDynamicDataPtr();
  size_t dynamicDataSize = project->getDynamicDataSize();
  const ParsedFlr& parsed = project->getParsedFlr();

  auto declareFailure = [&]() {
    // TODO what about shader recompile failed (where flr has parsed fine?)
    uint32_t failedCmd = EST_FAILED;
    memcpy(outStream, &failedCmd, 4);
  };

  if (project->hasFailed()) {
    declareFailure();
    return;
  }

  bool failed = false;
  size_t writeOffset = 0;
  auto serialize = [&](const void* src, size_t sz) {
    if (writeOffset + sz > streamSize) {
      declareFailure();
      failed = true;
    }
    if (failed)
      return;
    memcpy(outStream + writeOffset, src, sz);
    writeOffset += sz;
  };

  {
    uint32_t greetCmd = EST_GREET;
    serialize(&greetCmd, 4);
  }

  for (uint32_t bidx = 0; bidx < parsed.m_buffers.size(); bidx++) {
    const ParsedFlr::BufferDesc& buf = parsed.m_buffers[bidx];
    uint32_t cmd[] = { EST_BUFFER, bidx, buf.bufferCount };
    serialize(cmd, 12);
    serialize(buf.name.data(), buf.name.size() + 1);
  }

  for (uint32_t cidx = 0; cidx < parsed.m_computeShaders.size(); cidx++) {
    const ParsedFlr::ComputeShader& cs = parsed.m_computeShaders[cidx];
    uint32_t cmd[] = { EST_COMPUTE_SHADER, cidx };
    serialize(cmd, 8);
    serialize(cs.name.data(), cs.name.size() + 1);
  }

  for (uint32_t tidx = 0; tidx < parsed.m_taskBlocks.size(); tidx++) {
    const ParsedFlr::TaskBlock& tb = parsed.m_taskBlocks[tidx];
    uint32_t cmd[] = { EST_TASK, tidx };
    serialize(cmd, 8);
    serialize(tb.name.data(), tb.name.size() + 1);
  }

  for (const ParsedFlr::ConstFloat& c : parsed.m_constFloats) {
    uint32_t cmd = EST_CONST;
    serialize(&cmd, 4);
    char type = 'f';
    serialize(&type, 1);
    serialize(&c.value, 4);
    serialize(c.name.data(), c.name.size() + 1);
  }
  
  for (const ParsedFlr::ConstUint& c : parsed.m_constUints) {
    uint32_t cmd = EST_CONST;
    serialize(&cmd, 4);
    char type = 'I';
    serialize(&type, 1);
    serialize(&c.value, 4);
    serialize(c.name.data(), c.name.size() + 1);
  }

  for (const ParsedFlr::ConstInt& c : parsed.m_constInts) {
    uint32_t cmd = EST_CONST;
    serialize(&cmd, 4);
    char type = 'i';
    serialize(&type, 1);
    serialize(&c.value, 4);
    serialize(c.name.data(), c.name.size() + 1);
  }

  {
    uint32_t finishCmd = EST_FINISH;
    serialize(&finishCmd, 4);
  }
}

} // namespace flr_handshake

// TODO - pass in desired shared buffer size from cmdline args... ? (still
// need to clamp)
#define BUF_SIZE (1 << 30)

IpcProgram::IpcProgram() {
  m_writeDoneSemaphoreHandle = OpenSemaphoreW(
      SEMAPHORE_ALL_ACCESS,
      false,
      L"Global_FlrWriteDoneSemaphore");
  m_readDoneSemaphoreHandle = OpenSemaphoreW(
      SEMAPHORE_ALL_ACCESS,
      false,
      L"Global_FlrReadDoneSemaphore");
  m_sharedMemoryHandle =
      OpenFileMappingW(FILE_MAP_ALL_ACCESS, false, L"Global_FlrSharedMemory");
  m_sharedMemoryBuffer = nullptr;

  if (!m_writeDoneSemaphoreHandle || !m_readDoneSemaphoreHandle ||
      !m_sharedMemoryHandle) {
    std::cerr << "Could not initialize shared resources." << std::endl;
    throw std::runtime_error("Could not initialize shared resources.");
    return;
  }

  m_sharedMemoryBuffer =
      MapViewOfFile(m_sharedMemoryHandle, FILE_MAP_ALL_ACCESS, 0, 0, BUF_SIZE);

  if (!m_sharedMemoryBuffer) {
    std::cerr << "Could not map shared memory." << std::endl;
    throw std::runtime_error("Could not map shared memory.");
    return;
  }

  WaitForSingleObject(m_writeDoneSemaphoreHandle, INFINITE);

  char c[512];
  snprintf(c, 257, "%s", (char*)m_sharedMemoryBuffer);
  std::cerr << c << std::endl;

  // Warning: semaphore needs to be signalled once we do the handshake
  m_bHandshakePending = true;
}

IpcProgram::~IpcProgram() {
  if (m_sharedMemoryBuffer)
    UnmapViewOfFile(m_sharedMemoryBuffer);

  if (m_writeDoneSemaphoreHandle)
    CloseHandle(m_writeDoneSemaphoreHandle);
  if (m_readDoneSemaphoreHandle)
    CloseHandle(m_readDoneSemaphoreHandle);
  if (m_sharedMemoryHandle)
    CloseHandle(m_sharedMemoryHandle);
}

void IpcProgram::setupParams(FlrParams& params) {}

void IpcProgram::tick(Project* project, const FrameContext& frame) {
  if (m_bHandshakePending)
  {
    flr_handshake::establishProject(project, (char*)m_sharedMemoryBuffer, BUF_SIZE);
    char c[512];
    snprintf(c, 512, "%s", (char*)m_sharedMemoryBuffer);
    std::cerr << c << std::endl;

    ReleaseSemaphore(m_readDoneSemaphoreHandle, 1, nullptr);
    WaitForSingleObject(m_writeDoneSemaphoreHandle, INFINITE);

    snprintf(c, 512, "%s", (char*)m_sharedMemoryBuffer);
    std::cerr << c << std::endl;

    ReleaseSemaphore(m_readDoneSemaphoreHandle, 1, nullptr);

    m_bHandshakePending = false;
  }
}

void IpcProgram::draw(
    Project* project,
    VkCommandBuffer commandBuffer,
    const FrameContext& frame) {

  WaitForSingleObject(m_writeDoneSemaphoreHandle, INFINITE);

  //*project->getSliderFloat("TEST_SLIDER") = *(float*)m_sharedMemoryBuffer;
  bool result = flr_cmds::processCmdList(project, commandBuffer, frame, (char*)m_sharedMemoryBuffer, BUF_SIZE);
  if (!result)
    std::cerr << "Could not parse commandlist" << std::endl;

  ReleaseSemaphore(m_readDoneSemaphoreHandle, 1, nullptr);
}
} // namespace flr