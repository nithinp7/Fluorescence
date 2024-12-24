
#include <initguid.h>
#include <mmdeviceapi.h>
#include <Audioclient.h>

#include <vector>

namespace flr {
class Audio { // TODO: better name
public:
  Audio();
  ~Audio();

  void play();
  void copySamples(float* dst, uint32_t count) const;

private:
  IMMDevice* m_pRecorder;
  IMMDevice* m_pRenderer;
  IAudioClient* m_pRecorderClient;
  IAudioClient* m_pRenderClient;
  IAudioRenderClient* m_pRenderService;
  IAudioCaptureClient* m_pCaptureService;
  WAVEFORMATEX* m_pFormat;

  uint32_t m_sampleOffset;
  std::vector<float> m_samples;
};
} // namespace flr