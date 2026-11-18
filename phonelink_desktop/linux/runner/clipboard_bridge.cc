#include "clipboard_bridge.h"

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

static void text_received(GtkClipboard*, const gchar* text, gpointer data) {
  FlMethodCall* call = FL_METHOD_CALL(data);
  g_autoptr(FlValue) result =
      text != nullptr ? fl_value_new_string(text) : fl_value_new_null();
  fl_method_call_respond_success(call, result, nullptr);
  g_object_unref(call);
}

static void clipboard_method(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  GtkClipboard* clipboard = static_cast<GtkClipboard*>(data);
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "available") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(clipboard != nullptr);
    fl_method_call_respond_success(call, result, nullptr);
  } else if (clipboard == nullptr) {
    fl_method_call_respond_error(call, "unavailable",
                                 "Background clipboard unavailable", nullptr,
                                 nullptr);
  } else if (g_strcmp0(method, "readText") == 0) {
    gtk_clipboard_request_text(clipboard, text_received, g_object_ref(call));
  } else if (g_strcmp0(method, "writeText") == 0) {
    FlValue* value = fl_method_call_get_args(call);
    if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
      fl_method_call_respond_error(call, "invalid_text", "Text required",
                                   nullptr, nullptr);
      return;
    }
    gtk_clipboard_set_text(clipboard, fl_value_get_string(value), -1);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

FlMethodChannel* register_clipboard_bridge(FlView* view) {
  GtkClipboard* clipboard = nullptr;
#ifdef GDK_WINDOWING_X11
  GdkDisplay* display = gdk_display_get_default();
  if (!GDK_IS_X11_DISPLAY(display)) {
    const gchar* xdisplay = g_getenv("DISPLAY");
    // GTK owns opened displays and their clipboard objects until shutdown.
    // An explicit X display name leaves the default Wayland display untouched.
    display = xdisplay != nullptr ? gdk_display_open(xdisplay) : nullptr;
  }
  if (display != nullptr && GDK_IS_X11_DISPLAY(display)) {
    clipboard = gtk_clipboard_get_for_display(display, GDK_SELECTION_CLIPBOARD);
  }
#endif
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "phonelink/clipboard", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, clipboard_method, clipboard,
                                            nullptr);
  return channel;
}
