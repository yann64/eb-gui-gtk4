// eb-gui-gtk4 native shim - bridges eb-gui's own contract shape for
// GuiActionConnectTriggered (`SUB(userData AS ANY PTR)`, matching
// eb-qt6's own ActionConnectTriggered verbatim - see this package's
// README) to GTK4's real GSimpleAction "activate" signal shape
// (`void (*)(GSimpleAction*, GVariant*, gpointer)`). Same reasoning as
// shim_closecallback.h's own top comment: eBasic can produce a function
// pointer (`@ProcName`) but can't call through an arbitrary stored one
// itself, so only native code can actually re-dispatch with a
// different argument shape.
#pragma once

extern "C" {

typedef void (*EbGuiVoidCallback)(void* userData);

// Connects `cb`/`userData` to `action`'s "activate" signal, discarding
// the two leading GTK4-specific arguments (the action itself, and its
// parameter - always 0 for the plain, stateless actions this contract
// creates) before forwarding.
void eb_gui_gtk4_action_connect_triggered(void* action, EbGuiVoidCallback cb, void* userData);

}
