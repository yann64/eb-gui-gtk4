// eb-gui-gtk4 native shim - bridges eb-gui's own contract shape for
// GuiListBoxConnectSelectionChanged (`SUB(userData AS ANY PTR)`) to
// GtkListBox's real "row-selected" signal shape
// (`void (*)(GtkListBox*, GtkListBoxRow*, gpointer)`) - THREE real
// arguments, not two. This is deliberately its OWN dedicated
// trampoline, not a reuse of shim_userdatasignal.h's generic one
// (Round 4) - that one is fixed at exactly two parameters
// `(GObject*, gpointer)` and would silently misdeliver the real `row`
// pointer in place of `userData` if reused here, the same class of bug
// Round 4's own original GuiButtonConnectClicked/GuiEntryConnectChanged
// bug was. Same reasoning/technique as shim_actiontrigger.h's own
// bridge for GSimpleAction's real 3-arg "activate" signal.
#pragma once

extern "C" {

typedef void (*EbGuiVoidCallback)(void* userData);

// Connects `cb`/`userData` to `listBox`'s "row-selected" signal,
// discarding the two leading GTK4-specific arguments (the list box
// itself, and the newly-selected row) before forwarding.
void eb_gui_gtk4_listbox_connect_selection_changed(void* listBox, EbGuiVoidCallback cb, void* userData);

}
