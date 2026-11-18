#ifndef PHONELINK_CLIPBOARD_BRIDGE_H_
#define PHONELINK_CLIPBOARD_BRIDGE_H_

#include <flutter_linux/flutter_linux.h>

// Keeps window rendering on the native display while using the desktop's X11
// clipboard interoperability connection for background text access, if present.
FlMethodChannel* register_clipboard_bridge(FlView* view);

#endif
