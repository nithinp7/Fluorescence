#include "Fluorescence.h"

#include <Althea/Application.h>

#include <iostream>

using namespace AltheaEngine;

int main() {
  Application app("Fluorescence", "..", "../Extern/Althea", 1440, 1280);
   app.createGame<flr::Fluorescence>();

  try {
    app.run();
  } catch (const std::exception& e) {
    std::cerr << e.what() << std::endl;
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}