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
    case CMD_INVALID: {
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
        // TODO implement, need to write directly into UI uniform block (CPU copy)
        return false;
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

  ReleaseSemaphore(m_readDoneSemaphoreHandle, 1, nullptr);
  WaitForSingleObject(m_writeDoneSemaphoreHandle, INFINITE);

  snprintf(c, 257, "%s", (char*)m_sharedMemoryBuffer);
  std::cerr << c << std::endl;

  ReleaseSemaphore(m_readDoneSemaphoreHandle, 1, nullptr);
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