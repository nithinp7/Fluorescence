#include "Fluorescence.h"

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

  Application app("Fluorescence", "../..", "../../Extern/Althea", 1440, 1280);
  app.createGame<flr::Fluorescence>();

  flr::Fluorescence* game = app.getGameInstance<flr::Fluorescence>();
  if (argc > 1) {
    game->setStartupProject(argv[1]);
  }

  try {
    app.run();
  } catch (const std::exception& e) {
    std::cerr << e.what() << std::endl;
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}