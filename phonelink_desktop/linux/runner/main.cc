#include "my_application.h"

int main(int argc, char** argv) {
  // Use the desktop's native backend instead of forcing XWayland on Wayland.
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
