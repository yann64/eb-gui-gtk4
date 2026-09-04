#include "shim_actiontrigger.h"

#include <gio/gio.h>

namespace {

struct TriggerCallbackData {
    EbGuiVoidCallback callback;
    void* userData;
};

void OnActivate(GSimpleAction*, GVariant*, gpointer data) {
    auto* cd = static_cast<TriggerCallbackData*>(data);
    cd->callback(cd->userData);
}

void FreeTriggerCallbackData(gpointer data, GClosure*) { delete static_cast<TriggerCallbackData*>(data); }

} // namespace

extern "C" {

void eb_gui_gtk4_action_connect_triggered(void* action, EbGuiVoidCallback cb, void* userData) {
    auto* cd = new TriggerCallbackData{cb, userData};
    g_signal_connect_data(G_OBJECT(action), "activate", G_CALLBACK(OnActivate), cd, FreeTriggerCallbackData,
                           static_cast<GConnectFlags>(0));
}

}
