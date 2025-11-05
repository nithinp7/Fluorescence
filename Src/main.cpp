#if BUILD_FLR_APP

#include "Fluorescence.h"
#include "IpcProgram.h"

#include <Althea/Application.h>

#include <iostream>
#include <filesystem>
#include <Windows.h>


using namespace AltheaEngine;

int main(int argc, char* argv[]) {
  char exePathStr[512];
  GetModuleFileNameA(nullptr, exePathStr, 512);
  std::filesystem::path exeDir(exePathStr);
  exeDir.remove_filename();
  std::filesystem::current_path(exeDir);

  Application::CreateOptions options{};
  options.width = 1440;
  options.height = 1280;
  options.frameRateLimit = 30;
  Application app("Fluorescence", "../..", "../../Extern/Althea", &options);
  app.createGame<flr::Fluorescence>();

  flr::Fluorescence* game = app.getGameInstance<flr::Fluorescence>();
  flr::IpcProgram* ipc = nullptr;
  if (argc > 1) {
    game->setStartupProject(argv[1]);
  }
  if (argc > 2) {
    // TODO actually do something with argv[1]
    ipc = game->registerProgram<flr::IpcProgram>();
  }

  try {
    app.run();
  } catch (const std::exception& e) {
    std::cerr << e.what() << std::endl;
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}

#endif // BUILD_FLR_APP