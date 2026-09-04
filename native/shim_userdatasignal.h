// eb-gui-gtk4 native shim - generic bridge for every eb-gui contract
// signal that promises a bare SUB(userData AS ANY PTR) handler shape
// (GuiButtonConnectClicked/GuiEntryConnectChanged/GuiCheckBoxConnectToggled/
// GuiRadioButtonConnectToggled/GuiComboBoxConnectChanged) but whose real
// GTK4 signal always delivers (instance, ...signal-specific args...,
// user_data) - every signal this package connects this way has zero
// signal-specific args ("clicked"/"changed"/"toggled" are all plain
// void(GObject*, gpointer)), so the real shape always reduces to just
// (instance, user_data).
//
// A previous direct `ObjConnect(obj, signal, handler, userData)`
// pass-through (no shim at all) silently delivered the WRONG value to
// a 1-param eBasic handler - GLib's own marshaling calls
// handler(instance, user_data) positionally, so a handler declared
// with only ONE parameter binds it to `instance`, not `user_data`,
// exactly the same reasoning as shim_actiontrigger.h's own top comment
// (eBasic can't call through an arbitrary stored function pointer with
// a translated argument shape - only native code can re-dispatch).
// Confirmed by direct reproduction (a standalone spike printing the
// received pointer against both candidates) before fixing, not assumed.
#pragma once

extern "C" {

typedef void (*EbGuiVoidCallback)(void* userData);

void eb_gui_gtk4_connect_userdata_signal(void* obj, const char* signalName, EbGuiVoidCallback cb, void* userData);

}
