#include "shim_closecallback.h"

#include <gtk/gtk.h>

namespace {

struct CloseCallbackData {
    EbGuiCloseCallback callback;
    void* userData;
};

gboolean OnCloseRequest(GtkWindow*, gpointer data) {
    auto* cd = static_cast<CloseCallbackData*>(data);
    int allow = cd->callback(cd->userData);
    // Real GTK4 polarity: FALSE lets the default close handling proceed,
    // TRUE vetoes it - the opposite of eb-gui's own "nonzero = allow".
    return allow ? FALSE : TRUE;
}

void FreeCloseCallbackData(gpointer data, GClosure*) { delete static_cast<CloseCallbackData*>(data); }

} // namespace

extern "C" {

void eb_gui_gtk4_window_set_close_callback(void* window, EbGuiCloseCallback cb, void* userData) {
    auto* cd = new CloseCallbackData{cb, userData};
    g_signal_connect_data(G_OBJECT(window), "close-request", G_CALLBACK(OnCloseRequest), cd, FreeCloseCallbackData,
                           static_cast<GConnectFlags>(0));
}

}
