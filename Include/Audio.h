
#include <initguid.h>
#include <mmdeviceapi.h>
#include <Audioclient.h>

namespace flr {
class Audio { // TODO: better name
public:
  Audio();
  ~Audio();

  void play() const;

private:
  IMMDevice* m_pRecorder;
  IMMDevice* m_pRenderer;
  IAudioClient* m_pRecorderClient;
  IAudioClient* m_pRenderClient;
  IAudioRenderClient* m_pRenderService;
  IAudioCaptureClient* m_pCaptureService;
  WAVEFORMATEX* m_pFormat;
};
} // namespace flr