MyApplication* my_application_new() {
  return MY_APPLICATION(
      g_object_new(my_application_get_type(), "application-id", APPLICATION_ID,
                   "flags", G_APPLICATION_HANDLES_OPEN, nullptr));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be familiar with.
  //
  // If you wish to use Flutter's normal title bar for the window, pass
  // "false" to the gtk_header_bar_set_show_title_buttons utility.
  GtkWidget* header_bar = gtk_header_bar_new();
  gtk_widget_show(header_bar);
  gtk_header_bar_set_title(GTK_HEADER_BAR(header_bar), APPLICATION_NAME);
  gtk_header_bar_set_show_title_buttons(GTK_HEADER_BAR(header_bar), TRUE);
  gtk_window_set_titlebar(window, header_bar);

  gtk_window_set_title(window, "FruitNinja");
  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
} 