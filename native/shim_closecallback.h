// eb-gui-gtk4 native shim (one of two - see also shim_actiontrigger.h).
// eb-gui's own contract for GuiWindowSetCloseCallback matches
// eb-haiku's real BWindow::QuitRequested shape exactly
// (`FUNCTION(userData AS ANY PTR) AS INTEGER`, nonzero = allow the
// close) - deliberately chosen so eb-gui-qt6 needs ZERO native code
// (eb-qt6's own MainWindowSetCloseCallback already matches this shape
// verbatim). GTK4's real "close-request" signal has a different shape
// (`gboolean (*)(GtkWindow*, gpointer)`) AND the opposite polarity
// (TRUE = veto, not allow) - eBasic itself cannot bridge this: it can
// produce a function pointer (`@ProcName`) to hand to C, but has no way
// to *call through* an arbitrary stored function pointer itself (no
// callable function-pointer type exists in the language) - only native
// code can actually invoke one. Hence this trampoline.
//
// A plain C function suffices here, no C++ class/Q_OBJECT-style
// subclass needed at all (unlike eb-qt6/eb-haiku's own shims) - GTK4's
// signal system already dispatches through ordinary function pointers
// via g_signal_connect_data, the same mechanism eb-gtk4's own
// ObjConnect uses.
#pragma once

extern "C" {

typedef int (*EbGuiCloseCallback)(void* userData);

// Connects `cb`/`userData` to `window`'s "close-request" signal,
// translating eb-gui's contract shape/polarity to GTK4's real one.
// Safe to call more than once on the same window (each call adds
// another independent "close-request" handler, matching
// g_signal_connect_data's own semantics - not something this package's
// own callers are expected to rely on, just not actively guarded
// against either).
void eb_gui_gtk4_window_set_close_callback(void* window, EbGuiCloseCallback cb, void* userData);

}
