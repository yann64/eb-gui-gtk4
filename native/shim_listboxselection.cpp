#include "shim_listboxselection.h"

#include <gio/gio.h>
#include <gtk/gtk.h>

namespace {

struct ListBoxSelectionCallbackData {
    EbGuiVoidCallback callback;
    void* userData;
};

void OnRowSelected(GtkListBox*, GtkListBoxRow*, gpointer data) {
    auto* cd = static_cast<ListBoxSelectionCallbackData*>(data);
    cd->callback(cd->userData);
}

void FreeListBoxSelectionCallbackData(gpointer data, GClosure*) {
    delete static_cast<ListBoxSelectionCallbackData*>(data);
}

} // namespace

extern "C" {

void eb_gui_gtk4_listbox_connect_selection_changed(void* listBox, EbGuiVoidCallback cb, void* userData) {
    auto* cd = new ListBoxSelectionCallbackData{cb, userData};
    g_signal_connect_data(G_OBJECT(listBox), "row-selected", G_CALLBACK(OnRowSelected), cd,
                           FreeListBoxSelectionCallbackData, static_cast<GConnectFlags>(0));
}

}
