#include "shim_userdatasignal.h"

#include <gio/gio.h>

namespace {

struct UserDataSignalData {
    EbGuiVoidCallback callback;
    void* userData;
};

void OnGenericSignal(GObject*, gpointer data) {
    auto* sd = static_cast<UserDataSignalData*>(data);
    sd->callback(sd->userData);
}

void FreeUserDataSignalData(gpointer data, GClosure*) { delete static_cast<UserDataSignalData*>(data); }

} // namespace

extern "C" {

void eb_gui_gtk4_connect_userdata_signal(void* obj, const char* signalName, EbGuiVoidCallback cb, void* userData) {
    auto* sd = new UserDataSignalData{cb, userData};
    g_signal_connect_data(G_OBJECT(obj), signalName, G_CALLBACK(OnGenericSignal), sd, FreeUserDataSignalData,
                           static_cast<GConnectFlags>(0));
}

}
