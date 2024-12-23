#include "Audio.h"

#include <stdio.h>
#include <cassert>
#include <Windows.h>

namespace flr {

// TODO: Rename class to something more descriptive...

Audio::Audio() {
  HRESULT hr;
  IMMDeviceEnumerator* enumerator = NULL;

  // Initializes the COM library
  hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  assert(SUCCEEDED(hr));

  hr = CoCreateInstance(
    __uuidof(MMDeviceEnumerator),
    NULL,
    CLSCTX_ALL,
    __uuidof(IMMDeviceEnumerator),
    (void**)&enumerator
  );
  assert(SUCCEEDED(hr));

  // enumerate and choose recorder / renderer devices
  hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &m_pRecorder);
  assert(SUCCEEDED(hr));
  hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &m_pRenderer);
  assert(SUCCEEDED(hr));
  hr = enumerator->Release();
  assert(SUCCEEDED(hr));

  hr = m_pRecorder->Activate(__uuidof(IAudioClient), CLSCTX_ALL, NULL, (void**)&m_pRecorderClient);
  assert(SUCCEEDED(hr));

  // REVIEW BLOCK
  hr = m_pRenderer->Activate(__uuidof(IAudioClient), CLSCTX_ALL, NULL, (void**)&m_pRenderClient);
  assert(SUCCEEDED(hr));

  hr = m_pRecorderClient->GetMixFormat(&m_pFormat);
  assert(SUCCEEDED(hr));

  printf("Mix format:\n");
  printf("  Frame size     : %d\n", m_pFormat->nBlockAlign);
  printf("  Channels       : %d\n", m_pFormat->nChannels);
  printf("  Bits per second: %d\n", m_pFormat->wBitsPerSample);
  printf("  Sample rate:   : %d\n", m_pFormat->nSamplesPerSec);

  // REVIEW BLOCK
  hr = m_pRecorderClient->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 10000000, 0, m_pFormat, NULL);
  assert(SUCCEEDED(hr));

  hr = m_pRenderClient->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 10000000, 0, m_pFormat, NULL);
  assert(SUCCEEDED(hr));

  hr = m_pRenderClient->GetService(__uuidof(IAudioRenderClient), (void**)&m_pRenderService);
  assert(SUCCEEDED(hr));

  hr = m_pRecorderClient->GetService(__uuidof(IAudioCaptureClient), (void**)&m_pCaptureService);
  assert(SUCCEEDED(hr));


  hr = m_pRecorderClient->Start();
  assert(SUCCEEDED(hr));

  hr = m_pRenderClient->Start();
  assert(SUCCEEDED(hr));

}

Audio::~Audio() {
  m_pRecorderClient->Stop();
  m_pRenderClient->Stop();

  m_pCaptureService->Release();
  m_pRenderService->Release();

  m_pRecorderClient->Release();
  m_pRenderClient->Release();

  m_pRecorder->Release();
  m_pRenderer->Release();

  CoUninitialize();
}

void Audio::play() const {
  HRESULT hr;
  UINT32 nFrames;
  DWORD flags;
  BYTE* captureBuffer;
  BYTE* renderBuffer;

  for (int i = 0; i < 10; i++) {
    hr = m_pCaptureService->GetBuffer(&captureBuffer, &nFrames, &flags, NULL, NULL);
    assert(SUCCEEDED(hr));

    hr = m_pCaptureService->ReleaseBuffer(nFrames);
    assert(SUCCEEDED(hr));

    hr = m_pRenderService->GetBuffer(nFrames, &renderBuffer);
    assert(SUCCEEDED(hr));

    memcpy(renderBuffer, captureBuffer, m_pFormat->nBlockAlign * nFrames);

    hr = m_pRenderService->ReleaseBuffer(nFrames, 0);
    assert(SUCCEEDED(hr));
  }
}
} // namespace flr