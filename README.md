# eb-gui-gtk4

The GTK4 backend adapter for
[eb-gui](https://github.com/yann64/eb-gui), eBasic's universal,
cross-toolkit `Application`/`Window` API, managed with `ebpm`.

## Status

Phase 1: `Application`/`Window` only, implementing every function in
`eb-gui`'s own contract by calling into
[`eb-gtk4`](https://github.com/yann64/eb-gtk4). One piece of native code
(`native/shim_closecallback.h`/`.cpp`) - see "Why this package needs a
tiny native shim" below.

## Building

```sh
cmake -S native -B native/build
cmake --build native/build
EBASIC_LIBRARY_PATH=$(pwd)/native/build ebpm build
```

`EBASIC_LIBRARY_PATH` (not `LIBRARY_PATH` - see `ebpm`'s own docs for
why) tells `ebc`/`ebpm` where to find the just-built
`libebguigtk4.a` - this package's manifest has no field for a real,
external native library's own directory, the same gap `eb-qt6`/
`eb-haiku` document for their own native shims.

## Why this package needs a tiny native shim

`eb-gui`'s own `GuiWindowSetCloseCallback` contract matches
`eb-haiku`'s real `BWindow::QuitRequested` shape exactly -
`FUNCTION(userData AS ANY PTR) AS INTEGER`, nonzero = allow the close -
deliberately chosen so `eb-gui-qt6` needs zero native code at all
(`eb-qt6`'s own `MainWindowSetCloseCallback` already matches this shape
verbatim). GTK4's real `"close-request"` signal has a **different
shape** (`gboolean (*)(GtkWindow*, gpointer)`) **and the opposite
polarity** (`TRUE` = veto, not allow).

eBasic itself cannot bridge this: `@ProcName` produces a function
pointer to *hand to* C, but there is no way to *call through* an
arbitrary stored function pointer from eBasic code itself - no callable
function-pointer type exists in the language (confirmed by checking the
compiler's own `docs/reference/extern-interop.md` and
`namespaces-pointers-unions.md` - every existing callback mechanism in
this ecosystem, `eb-gtk4`'s `ObjConnect`, `eb-qt6`/`eb-haiku`'s own
`Shim*` classes, all pass the user's `@ProcName` straight through as the
*real* native callback; none of them ever redispatch through a second,
dynamically-stored pointer). So bridging GTK4's shape/polarity to
`eb-gui`'s contract needs a real trampoline written in C++, not eBasic -
`native/shim_closecallback.cpp`, a plain C function (no `Q_OBJECT`-style
subclass needed at all, since GTK4's signal system already dispatches
through ordinary function pointers via `g_signal_connect_data`).

## A real bug caught before shipping: window construction needs eager registration

`eb-gui`'s contract lets application code create and show windows
synchronously, immediately after `NewGuiApplication` - no `"activate"`
signal handler required, unlike `eb-gtk4`'s own idiomatic convention
(every one of its own examples builds UI inside an `"activate"`
handler). **Confirmed by direct reproduction**: skipping that convention
and constructing/presenting a `GtkApplicationWindow` before the owning
`GApplication` has been registered segfaults. Fixed by calling
`g_application_register()` explicitly inside `NewGuiApplication`
(safe to call more than once - a no-op if already registered) -
verified afterward that eager window construction/presentation works
correctly with no crash.

One harmless, expected side effect of this design: GTK4 prints
`GLib-GIO-WARNING: Your application does not implement
g_application_activate() and has no handlers connected to the
'activate' signal` to stderr, since this adapter never connects one
(everything happens eagerly instead) - cosmetic only, not a real
problem.

## Ownership and the quit model

Every window is created via `gtk_application_window_new`, so real
GTK4's own `GApplication` window tracking makes `GuiApplicationRun`
return once the last one closes, with no extra bookkeeping needed in
this adapter at all (contrast `eb-gui-qt6`, which has to track its own
live-window count since Qt's `QApplication` doesn't do this natively).

## Using as a dependency

```toml
[dependencies]
gui-gtk4 = { git = "https://github.com/yann64/eb-gui-gtk4.git" }
```

```basic
' Only the adapter's own interface is needed - it already carries a
' full copy of GuiApplication/GuiWindow (it #includes gui.iface.bas
' itself), so #including gui.iface.bas too would redeclare both TYPEs.
#include "gui-gtk4.iface.bas"

DIM app AS GuiApplication
app = NewGuiApplication("io.github.you.yourapp")

DIM win AS GuiWindow
win = NewGuiWindow(app, "Hello", 320, 240)
CALL GuiWindowShow(win)

CALL GuiApplicationRun(app)
```

## Verifying

- `examples/hello_window` - a plain window appears, title set through
  the universal API (screenshot-verified live on this host).
- `examples/verify` - headless(-ish) verification of every contract
  function: `GuiWindowSetEnabled`/`IsEnabled` round-tripped correctly;
  `GuiWindowSetModal`/`ClearModal`/`Move` (a documented best-effort
  no-op on this backend, confirmed via `GuiWindowCanMove() = 0`) and
  `GuiWindowSetCloseCallback` all connected without crashing (the
  underlying close-callback veto/allow/no-callback behavior is already
  directly verified at the `eb-gtk4` layer, `window_lifecycle_verify.bas`);
  `GuiApplicationQuit` stopped `GuiApplicationRun` promptly, no hang.

## See also

- [`eb-gui`](https://github.com/yann64/eb-gui) - the shared contract this package implements.
- [`eb-gui-qt6`](https://github.com/yann64/eb-gui-qt6) - the Qt6 adapter.
- [`eb-gtk4`](https://github.com/yann64/eb-gtk4) - the underlying GTK4 binding.
