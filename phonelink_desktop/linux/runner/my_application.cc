#include "my_application.h"
#include "clipboard_bridge.h"

#include <flutter_linux/flutter_linux.h>
#include <gmodule.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  GObject* indicator;
  GModule* indicator_module;
  gboolean tray_connected;
  gboolean start_in_tray;
  gboolean startup_pending;
  FlMethodChannel* clipboard_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void show_window(MyApplication* self) {
  self->start_in_tray = FALSE;
  self->startup_pending = FALSE;
  if (self->window != nullptr) {
    gtk_widget_show(GTK_WIDGET(self->window));
    gtk_window_present(self->window);
  }
}

static void open_from_tray(GtkMenuItem*, MyApplication* self) {
  show_window(self);
}

static void quit_from_tray(GtkMenuItem*, MyApplication* self) {
  g_application_quit(G_APPLICATION(self));
}

static void tray_connection_changed(GObject*, gboolean connected,
                                    MyApplication* self) {
  self->tray_connected = connected;
  if (connected) self->startup_pending = FALSE;
  // A panel restart must never leave the app hidden without a way to reopen it.
  if (!connected && !self->startup_pending && self->window != nullptr &&
      !gtk_widget_get_visible(GTK_WIDGET(self->window))) {
    show_window(self);
  }
}

static gboolean close_to_tray(GtkWidget* window, GdkEvent*, MyApplication* self) {
  if (!self->tray_connected) return FALSE;
  gtk_widget_hide(window);
  return TRUE;
}

static void create_tray(MyApplication* self, const gchar* icon_path) {
  const gchar* libraries[] = {"libayatana-appindicator3.so.1",
                              "libappindicator3.so.1", nullptr};
  for (int i = 0; libraries[i] != nullptr; ++i) {
    self->indicator_module = g_module_open(libraries[i], G_MODULE_BIND_LAZY);
    if (self->indicator_module != nullptr) break;
  }
  if (self->indicator_module == nullptr) return;

  GObject* (*create)(const gchar*, const gchar*, int) = nullptr;
  void (*set_status)(GObject*, int) = nullptr;
  void (*set_menu)(GObject*, GtkMenu*) = nullptr;
  if (!g_module_symbol(self->indicator_module, "app_indicator_new",
                       reinterpret_cast<gpointer*>(&create)) ||
      !g_module_symbol(self->indicator_module, "app_indicator_set_status",
                       reinterpret_cast<gpointer*>(&set_status)) ||
      !g_module_symbol(self->indicator_module, "app_indicator_set_menu",
                       reinterpret_cast<gpointer*>(&set_menu))) {
    g_module_close(self->indicator_module);
    self->indicator_module = nullptr;
    return;
  }
  // The GObject type callbacks remain valid until the process exits.
  g_module_make_resident(self->indicator_module);
  self->indicator = create(APPLICATION_ID, icon_path, 0);
  if (self->indicator == nullptr) return;
  g_signal_connect(self->indicator, "connection-changed",
                    G_CALLBACK(tray_connection_changed), self);

  GtkWidget* menu = gtk_menu_new();
  GtkWidget* open = gtk_menu_item_new_with_label("Open PhoneLink");
  g_signal_connect(open, "activate", G_CALLBACK(open_from_tray), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), open);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
  GtkWidget* quit = gtk_menu_item_new_with_label("Quit PhoneLink");
  g_signal_connect(quit, "activate", G_CALLBACK(quit_from_tray), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit);
  gtk_widget_show_all(menu);
  set_menu(self->indicator, GTK_MENU(menu));
  set_status(self->indicator, 1);  // APP_INDICATOR_STATUS_ACTIVE
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  if (!self->start_in_tray) {
    gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  }
}

static gboolean startup_tray_fallback(gpointer data) {
  MyApplication* self = MY_APPLICATION(data);
  self->startup_pending = FALSE;
  if (self->start_in_tray && !self->tray_connected) show_window(self);
  return G_SOURCE_REMOVE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    show_window(self);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->window));
  g_signal_connect(window, "delete-event", G_CALLBACK(close_to_tray), self);
  if (self->start_in_tray) {
    g_timeout_add_seconds_full(G_PRIORITY_DEFAULT, 3, startup_tray_fallback,
                                g_object_ref(self), g_object_unref);
  }

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "PhoneLink");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "PhoneLink");
  }

  gtk_window_set_default_size(window, 1280, 850);
  gtk_window_set_icon_name(window, APPLICATION_ID);

  // The bundle carries the same icon as the installed desktop launcher.
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* icon_path = g_build_filename(directory, "data", "phonelink.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_IS_REGULAR)) {
      gtk_window_set_icon_from_file(window, icon_path, nullptr);
      create_tray(self, icon_path);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->clipboard_channel = register_clipboard_bridge(view);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // The login launcher starts quietly; an ordinary launch opens the window.
  g_autoptr(GPtrArray) dart_arguments = g_ptr_array_new();
  for (int i = 1; (*arguments)[i] != nullptr; ++i) {
    if (g_strcmp0((*arguments)[i], "--start-in-tray") == 0) {
      self->start_in_tray = TRUE;
      self->startup_pending = TRUE;
    } else {
      g_ptr_array_add(dart_arguments, (*arguments)[i]);
    }
  }
  g_ptr_array_add(dart_arguments, nullptr);
  self->dart_entrypoint_arguments =
      g_strdupv(reinterpret_cast<gchar**>(dart_arguments->pdata));

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  if (!g_application_get_is_remote(application) || !self->start_in_tray) {
    g_application_activate(application);
  }
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->clipboard_channel);
  g_clear_object(&self->indicator);
  if (self->indicator_module != nullptr) {
    g_module_close(self->indicator_module);
    self->indicator_module = nullptr;
  }
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("PhoneLink");
  gtk_window_set_default_icon_name(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     static_cast<GApplicationFlags>(0), nullptr));
}
