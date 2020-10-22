//#include <gtk/gtk.h>
//
//static void
//activate (GtkApplication* app,
//          gpointer        user_data)
//{
//  GtkWidget *window;
//
//  window = gtk_application_window_new (app);
//  gtk_window_set_title (GTK_WINDOW (window), "Window");
//  gtk_window_set_default_size (GTK_WINDOW (window), 200, 200);
//  gtk_widget_show_all (window);
//}
//
//int
//main (int    argc,
//      char **argv)
//{
//  GtkApplication *app;
//  int status;
//
//  app = gtk_application_new ("org.gtk.example", G_APPLICATION_FLAGS_NONE);
//  g_signal_connect (app, "activate", G_CALLBACK (activate), NULL);
//  status = g_application_run (G_APPLICATION (app), argc, argv);
//  g_object_unref (app);
//
//  return status;
//}

const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

//extern fn gtk_application_new(text: [*:0]const u8, flags: c_int) ?*c.GtkApplication;

fn activate(app: *c.GtkApplication, data: c.gpointer) callconv(.C) void {
    //var win : *c.GtkWindow =
}

pub fn main() !void {
    var app: *c.GtkApplication = c.gtk_application_new("org.gtk.example", .G_APPLICATION_FLAGS_NONE) orelse @panic("E");
    _ = c.g_signal_connect_data(app, "activate", null, activate, null, @intToEnum(c.GConnectFlags, 0));
    _ = c.g_application_run(@ptrCast([*c]c.GApplication, app), 0, null);
    c.g_object_unref(app);
}
