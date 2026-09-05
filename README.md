# eb-gui-gtk4

The GTK4 backend adapter for
[eb-gui](https://github.com/yann64/eb-gui), eBasic's universal,
cross-toolkit `Application`/`Window` API, managed with `ebpm`.

## Status

**Confirmed running on Haiku, unmodified** (2026-09-04) - real
HaikuPorts `gtk4`, this package's own native shim, and `examples/verify`
all work with zero source changes; see `eb-gtk4`'s own README for the
platform detail (Haiku's GTK4 port uses its own native GDK backend).

Phase 1 (`Application`/`Window`) plus all of Phase 2
(`StatusBar`/`Timer`/`Menu`/`Toolbar`/`Action`), plus Widget/Layout
Round 1 (`GuiButton`/`GuiLabel`/`GuiEntry` + `GuiBox`/`GuiGrid`),
implementing every function in `eb-gui`'s own contract by calling into
[`eb-gtk4`](https://github.com/yann64/eb-gtk4). Two pieces of native
code (`native/shim_closecallback.h`/`.cpp`,
`native/shim_actiontrigger.h`/`.cpp`) - see "Why this package needs a
tiny native shim" below. `GuiTimer` maps onto `eb-gtk4`'s own
`GtkTimer` (itself backed by a small native shim in that package - see
`eb-gtk4`'s own README); `GuiTimerDestroy` is meaningful here (unlike
on Qt6), since `GtkTimer` isn't a GObject and needs its own explicit
free.

`GuiBox`/`GuiGrid` are the simplest of the three adapters to implement:
real GTK4 `Box`/`Grid` are themselves `Widget`s, so `GuiBox.handle`/
`GuiGrid.handle` ARE the real widget handles directly - no holder
widget needed the way `eb-gui-qt6`/`eb-gui-haiku` each require (see
`eb-gui`'s own README on this asymmetry). `GuiButtonConnectClicked`
has no programmatic "invoke this click" counterpart - real GTK4 has no
`gtk_button_clicked()` any more (removed upstream) and no generic
activate-by-action-name path for a plain button the way menu
actions/toolbar buttons get via `Action`/`ActionActivate` - `examples/
verify` only confirms connecting doesn't crash for this one function,
the same "real interactive input isn't headlessly driveable" limit
already documented elsewhere in this ecosystem.

`GuiMenuAddAction`/`GuiToolBarAddAction` paper over a real capability
mismatch: real GTK4 actions (`GSimpleAction`) are shareable,
window-scoped objects independent of any menu, but `eb-gui`'s own
contract follows Qt6's simpler "create a fresh action per call" shape
instead (see `eb-gui`'s own README). This adapter fakes that shape on
top of GTK4's richer model by registering a brand-new, uniquely-named
action on the owning window every time either function is called -
tracked via a small association table this package keeps for itself
(`EbGuiGtk4AssocSet`/`Get` in `src/lib.bas`), since `eb-gtk4`'s own
`g_object_get_data`/`set_data` (which it uses internally for the same
purpose) are raw-layer-only and don't cross the `--lib` package
boundary into this adapter's own public surface. The same table also
gives `GuiWindowStatusBar` its own auto-created-once memory (unlike
`GuiWindowMenuBar`/`GuiWindowToolBar`, which get that for free from
`eb-gtk4`'s own `WindowMenuBar`/`WindowToolBar`) and now composes it
with menu/toolbar through the same shared `WindowContentBox`
(`eb-gtk4` v0.11.0+) regardless of call order.

Real GTK4 tool bars are plain `Box`-of-`Button`s (GTK4 removed
`GtkToolbar` upstream), not action-based - `GuiToolBarAddAction` bridges
this by creating a real window-scoped `Action` alongside the button and
forwarding the button's own `"clicked"` signal into the action's
`"activate"`, via one fixed, reusable forwarding handler
(`EbGuiGtk4ToolbarButtonClicked`) parameterized by `userData` (the
standard callback-with-userData trampolining pattern this whole
ecosystem already relies on, since eBasic can't generate a distinct
closure per call) - so the returned `GuiAction` behaves identically
whether it came from a menu or a tool bar.

## Building

```sh
cmake -S native -B native/build
cmake --build native/build
EBASIC_LIBRARY_PATH=$(pwd)/native/build:$(pwd)/../eb-gtk4/native/build ebpm build
```

`EBASIC_LIBRARY_PATH` (not `LIBRARY_PATH` - see `ebpm`'s own docs for
why) tells `ebc`/`ebpm` where to find the just-built
`libebguigtk4.a` **and** `eb-gtk4`'s own `libebgtk4shim.a` (needed for
`GtkTimer`) - this package's manifest has no field for a real,
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

The same reasoning applies to `GuiActionConnectTriggered`: `eb-gui`'s
contract handler shape is `SUB(userData AS ANY PTR)` (matching
`eb-qt6`'s own `ActionConnectTriggered` verbatim), but real
`GSimpleAction`'s `"activate"` signal has a different shape
(`void (*)(GSimpleAction*, GVariant*, gpointer)`) - `native/
shim_actiontrigger.cpp` bridges it the same way, discarding the two
leading GTK4-specific arguments before forwarding.

## A real, shipped bug found and fixed this round: `GuiButtonConnectClicked`/`GuiEntryConnectChanged` delivered the WRONG value

`GuiButtonConnectClicked`/`GuiEntryConnectChanged` originally used a
**direct** `ObjConnect(obj, "clicked"/"changed", handler, userData)`
pass-through, with no shim at all - reasoning (never verified) that
since these signals carry no signal-specific arguments, the native
shape would already match the contract's own `SUB(userData AS ANY
PTR)` shape. **This was wrong, and shipped wrong through `v0.6.0`**:
real GTK4 signal marshaling always calls a connected handler as
`handler(instance, user_data)` - a genuinely different shape,
`(GObject*, gpointer)`. A 1-parameter eBasic handler still binds its
own sole parameter to the FIRST real argument, `instance`, not
`user_data` - so every existing `GuiButtonConnectClicked`/
`GuiEntryConnectChanged` caller was silently receiving the *widget's
own handle* in place of whatever real `userData` it had actually
passed at connect time.

Confirmed by direct reproduction, not assumed: a standalone spike
connected a real `"clicked"` signal, fired it via
`g_signal_emit_by_name`, and printed the received pointer against both
candidates - it matched the button's own handle, never the real
passed-in address. `eb-gtk4`'s own examples (e.g.
`examples/hello_window`) always declare the correct 2-parameter shape
(`SUB OnButtonClicked(btn AS GObj PTR, data AS ANY PTR)`) for exactly
this reason - only `eb-gui-gtk4`'s own contract-shape adapter code had
collapsed it to 1 parameter without the shim needed to make that safe.
`eb-gui-qt6`/`eb-gui-haiku` were never affected: Qt6's own shims are
real per-call C++ lambdas that already capture and deliver only
`userData` (`eb_qt6_button_connect_clicked`), and Haiku's `ShimHandler`
dispatch is likewise real custom C++ code, not a generic signal
pass-through - both confirmed not merely assumed before ruling them
out.

**Fixed** via a new, reusable native shim
(`native/shim_userdatasignal.cpp`), `eb_gui_gtk4_connect_userdata_signal`
- the same "generic bridge, one struct + one trampoline" technique
`shim_actiontrigger.cpp` already used for `GuiActionConnectTriggered`,
generalized since every affected signal (`"clicked"`, `"changed"`,
`"toggled"`) reduces to the identical real shape. `GuiButtonConnectClicked`/
`GuiEntryConnectChanged` now route through it, and Round 4's own
`GuiCheckBoxConnectToggled`/`GuiRadioButtonConnectToggled`/
`GuiComboBoxConnectChanged` (below) were built correctly on it from the
start. Verified via `examples/verify`'s own new regression check
(connects with a known marker address, fires the signal, asserts the
handler received exactly that address).

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
this adapter at all. `eb-gui-qt6` needs none either, as it turns out -
see that package's own README for a real, confirmed-not-assumed
correction to this project's original plan (Qt's own
`quitOnLastWindowClosed` already handles it).

**Also confirmed real and worth knowing**: on Qt6,
`GuiApplicationQuit` implicitly tries to close every currently-shown
window first, so a permanently-vetoing `GuiWindowSetCloseCallback` on a
shown window can silently block it too. GTK4 has no such negotiation -
`GuiApplicationQuit` here always stops unconditionally regardless of
any window's close callback (see `eb-gui-qt6`'s own README for the
full detail and the bug this caused there).

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

`GuiStatusBar`/`GuiTimer`:

```basic
DIM sb AS GuiStatusBar
sb = GuiWindowStatusBar(win)   ' auto-created, one per window
CALL GuiStatusBarShowMessage(sb, "Ready")
CALL GuiStatusBarClear(sb)

DIM t AS GuiTimer
t = NewGuiTimer(win)   ' parent required for the Qt6 adapter; ignored here
CALL GuiTimerSetInterval(t, 1000)
CALL GuiTimerSetSingleShot(t, 0)

SUB OnTick(userData AS ANY PTR)
    PRINT "tick"
END SUB
CALL GuiTimerConnectTimeout(t, @OnTick, 0)
CALL GuiTimerStart(t)
```

`GuiMenuBar`/`GuiToolBar`/`GuiAction`:

```basic
DIM bar AS GuiMenuBar
bar = GuiWindowMenuBar(win)   ' auto-created, one per window
DIM fileMenu AS GuiMenu
fileMenu = GuiMenuBarAddMenu(bar, "File")
DIM openAction AS GuiAction
openAction = GuiMenuAddAction(fileMenu, "Open...")

SUB OnOpen(userData AS ANY PTR)
    PRINT "open"
END SUB
CALL GuiActionConnectTriggered(openAction, @OnOpen, 0)

DIM tb AS GuiToolBar
tb = GuiWindowToolBar(win)   ' auto-created, one per window
DIM goAction AS GuiAction
goAction = GuiToolBarAddAction(tb, "Go")
CALL GuiActionConnectTriggered(goAction, @OnOpen, 0)
```

`GuiBox`/`GuiGrid`/widgets:

```basic
DIM box AS GuiBox
box = NewGuiBox(1, 8)   ' 1 = vertical

DIM lbl AS GuiLabel
lbl = NewGuiLabel("Type something, then click Go")
CALL GuiBoxAddChild(box, lbl.handle)

DIM entry AS GuiEntry
entry = NewGuiEntry("")
CALL GuiBoxAddChild(box, entry.handle)

SUB OnGo(userData AS ANY PTR)
    DIM e AS GuiEntry
    e.handle = userData
    PRINT GuiEntryGetText(e)
END SUB

DIM btn AS GuiButton
btn = NewGuiButton("Go")
CALL GuiButtonConnectClicked(btn, @OnGo, entry.handle)
CALL GuiBoxAddChild(box, btn.handle)

CALL GuiWindowSetContent(win, box.handle)
```

Round 2 constraints (expand/align/weight):

```basic
DIM growBtn AS GuiButton
growBtn = NewGuiButton("Grows")
CALL GuiBoxAddChildEx(box, growBtn.handle, 1.0, GUI_ALIGN_FILL, GUI_ALIGN_CENTER)

DIM fixedBtn AS GuiButton
fixedBtn = NewGuiButton("Fixed")
CALL GuiBoxAddChildEx(box, fixedBtn.handle, 0.0, GUI_ALIGN_END, GUI_ALIGN_START)
```

GTK4 puts expand/alignment on the CHILD widget itself, not the Box -
`GuiBoxAddChildEx`/`GuiGridAttachEx` call the new `WidgetSetHExpand`/
`VExpand`/`HAlign`/`VAlign` (`eb-gtk4` v0.12.0+) on `child` before
appending/attaching it, exactly as if you'd called them yourself first.
`expand` is boolean here (zero vs. nonzero) - real GTK4 has no
fractional-ratio expand between multiple expanding siblings, unlike
Qt6's stretch factor or Haiku's item weight (accepted, documented
loss - see `eb-gui`'s own README). `GuiGridSetColumnWeight`/
`SetRowWeight` are a documented no-op here - `GtkGrid` has no
per-column/row weight concept in real GTK4 at all.

Round 3 explicit min/max size:

```basic
CALL GuiWidgetSetMinSize(entry.handle, 200, 40)
CALL GuiWidgetSetMaxSize(entry.handle, 400, 40)   ' documented no-op here
```

`GuiWidgetSetMinSize` is a direct pass-through to the existing
`WidgetSetSizeRequest` (`gtk_widget_set_size_request`, already bound -
no prerequisite native work needed this round). `GuiWidgetSetMaxSize`
is a documented, accepted no-op - real GTK4 has no generic per-widget
maximum-size API at all (confirmed via this host's own `gtkwidget.h`,
not assumed - only individual widget classes like `GtkLabel` have
unrelated, narrower properties). Note min/max size are a floor/ceiling
on what the layout may allocate, not a growth mechanism by
themselves - pair with `GuiBoxAddChildEx`'s own `expand` parameter
(Round 2) if you want a constrained item to also visibly grow into
leftover space.

## Widgets (Round 4) - CheckBox, RadioButton, ComboBox

```basic
DIM cb AS GuiCheckBox
cb = NewGuiCheckBox("Enable feature")
CALL GuiCheckBoxSetChecked(cb, 1)

DIM r1 AS GuiRadioButton
r1 = NewGuiRadioButton("Option A")
DIM r2 AS GuiRadioButton
r2 = NewGuiRadioButton("Option B")
CALL GuiRadioButtonSetGroup(r2, r1)   ' r1/r2 now mutually exclusive

DIM combo AS GuiComboBox
combo = NewGuiComboBox()
CALL GuiComboBoxAddItem(combo, "First")
CALL GuiComboBoxAddItem(combo, "Second")
CALL GuiComboBoxSetSelectedIndex(combo, 0)
PRINT GuiComboBoxGetSelectedText(combo)
```

Real GTK4 unifies checkbox and radio-button into ONE widget class,
`CheckButton` (`eb-gtk4` v0.13.0) - `GuiCheckBox`/`GuiRadioButton` both
wrap the exact same underlying widget, the contract-level TYPE being
the only thing distinguishing their role. `GuiRadioButtonSetGroup`
calls `CheckButtonSetGroup` directly - real GTK4 has no separate group
object at all, unlike Qt6's own `QButtonGroup`. `GuiComboBox` binds
`ComboBoxText` (`GtkComboBoxText`, deprecated-but-simple, chosen over
the heavier `GtkDropDown` - see `eb-gtk4`'s own README).
`GuiComboBoxGetSelectedText` deliberately leaks a small per-call
buffer, same accepted precedent as `eb-gui-qt6`'s own `GuiButtonGetText`
- real `gtk_combo_box_text_get_active_text` returns a freshly
allocated string and the contract has no matching free function.

## Widgets (Round 5) - ProgressBar, Slider

```basic
DIM pb AS GuiProgressBar
pb = NewGuiProgressBar()
CALL GuiProgressBarSetRange(pb, 0, 200)
CALL GuiProgressBarSetValue(pb, 150)

DIM slider AS GuiSlider
slider = NewGuiSlider(0)   ' 0 = horizontal
CALL GuiSliderSetRange(slider, 0, 200)
CALL GuiSliderSetValue(slider, 150)
```

Real GTK4's `GtkProgressBar` (`eb-gtk4` v0.14.0) has no integer
min/max/value model at all - just a `0.0-1.0` double fraction. This
adapter tracks each progress bar's own `(min, max, value)` in a small
internal association table, computing the fraction for display
(`gtk_progress_bar_set_fraction`) and returning the tracked integer
directly for `GetValue` - never re-deriving it from the lossy
fraction. `GuiSlider` wraps `Scale` (a real `GtkRange`) directly, real
integer values throughout. `GuiSliderConnectValueChanged` reuses the
Round 4 `eb_gui_gtk4_connect_userdata_signal` trampoline on
`GtkRange`'s own `"value-changed"` signal - already correctly fixed to
deliver only `userData`, verified again by this round's own regression
check.

## Widgets (Round 6) - ListBox, TextView

```basic
DIM lb AS GuiListBox
lb = NewGuiListBox()
CALL GuiListBoxAddItem(lb, "First")
CALL GuiListBoxAddItem(lb, "Second")
CALL GuiListBoxSetSelectedIndex(lb, 1)
PRINT GuiListBoxGetSelectedIndex(lb)   ' 1
PRINT GuiListBoxGetItemText(lb, 0)     ' First

DIM tv AS GuiTextView
tv = NewGuiTextView()
CALL GuiTextViewSetText(tv, "hello")
PRINT GuiTextViewGetText(tv)
```

`GuiListBox` wraps `eb-gtk4`'s own `ListBox`/`ListBoxRow` (v0.15.0),
which this round extended with real selection primitives
(`gtk_list_box_get_selected_row`/`select_row`) and a way to read a
row's own appended child widget back
(`gtk_list_box_row_get_child`). `GuiListBoxAddItem` wraps each item's
text in a plain `Label` and appends it as a row; `GetItemText` reads
that same `Label` back via `ListBoxRowGetChild` - **no internal
item-tracking table needed**, unlike `GuiComboBox` (real
`GtkComboBoxText`'s own underlying item type has no label getter at
all).

**A real ABI trap caught by this round's own research and a
standalone spike, before it could become a second version of the
Round 4 bug**: real GTK4's `"row-selected"` signal has the shape
`(GtkListBox*, GtkListBoxRow*, gpointer)` - **three** real arguments,
not two. The existing Round 4 generic trampoline
(`eb_gui_gtk4_connect_userdata_signal`, used by `"clicked"`/
`"changed"`/`"toggled"`/`"value-changed"`) is fixed at exactly two
parameters (`GObject*, gpointer`) and would silently misdeliver the
real `GtkListBoxRow*` in place of `userData` if reused here - the
exact same failure class the Round 4 investigation found and fixed
for `GuiButtonConnectClicked`. `GuiListBoxConnectSelectionChanged`
instead uses a NEW, dedicated 3-parameter native trampoline
(`shim_listboxselection.cpp`, mirroring `shim_actiontrigger.cpp`'s own
technique for `GSimpleAction`'s real 3-arg `"activate"` signal) that
discards the leading `GtkListBox*`/`GtkListBoxRow*` arguments before
forwarding only `userData`. This was verified correct via a standalone
spike (connecting a known marker address, selecting a row
programmatically, and asserting the received pointer matched the
marker - not the row, not the list box) *before* being wired into the
permanent adapter code, and `examples/verify` carries the same
regression check.

`GuiTextView` wraps `eb-gtk4`'s already-generic `TextView`/`TextBuffer`
directly (`NewTextView`+`TextViewGetBuffer`+`TextBufferSetText`/
`GetText`+`TextViewSetEditable` - no new native work needed).
`GuiTextViewGetText` leaks a small per-call buffer, the same
documented tradeoff as `GuiComboBoxGetSelectedText` (real
`gtk_text_buffer_get_text` returns a newly `g_malloc`'d string with no
matching free function in the contract).

`GuiTextView` deliberately has no `ConnectTextChanged` this round -
see `eb-gui`'s own README for why (a Haiku prerequisite, not a GTK4
limitation).

`GuiScrollBar` was deliberately excluded this round - real GTK4's
`GtkScrolledWindow` already auto-manages its own scrollbars for any
child, making a standalone scrollbar binding low-value (see `eb-gui`'s
own README for the full cross-backend reasoning).

## Widgets (Round 7) - settable preferred size, a documented no-op

`GuiWidgetSetPreferredSize` is a documented, accepted no-op on this
backend - real GTK4's own "natural size" is a READ-ONLY query
(`gtk_widget_measure`, computed per-widget-class by its own `measure`
vfunc), not a settable property on the generic `GtkWidget` base -
confirmed via direct header inspection. See `eb-gui`'s own README for
the full Round 7 writeup, including the real Haiku hardware finding
that turned this into a no-op on ALL THREE backends, not just this
one.

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
  `GuiStatusBar` show/clear didn't crash (real `GtkStatusbar` rendering
  is already screenshot-verified at the `eb-gtk4` layer,
  `examples/statusbar_timer`); and `GuiTimer` driving a real,
  running-loop `GuiApplicationQuit` (a single-shot timer's own callback
  calls it) - the program exiting promptly rather than hanging proves
  the interval/single-shot/callback-dispatch and quit all genuinely
  work together, a more realistic shape than an earlier quit-before-run
  ordering this same example used before `GuiTimer` existed;
  `GuiWindowMenuBar`/`GuiWindowToolBar` return the identical handle on
  repeated calls; `GuiActionTrigger` genuinely reaches a connected
  `GuiActionConnectTriggered` handler for both a menu action and a tool
  bar action; `GuiActionSetEnabled` round-trips without crashing; the
  menu bar/tool bar/status bar all compose correctly on the same
  window regardless of call order (shared `WindowContentBox`);
  `GuiEntrySetText`/`GetText` round-trip correctly through a `GuiGrid`
  nested inside a `GuiBox`; `GuiWindowSetContent` composes with
  StatusBar/MenuBar/ToolBar on the same window without crashing; and
  `GuiBoxAddChildEx`/`GuiGridAttachEx`/`GuiGridSetColumnWeight`/
  `SetRowWeight` (Round 2 constraints) run without crashing, including
  a `GuiGrid` nested inside a constrained `GuiBox` child;
  `GuiWidgetSetMinSize`/`SetMaxSize` (Round 3) run without crashing;
  `GuiButtonConnectClicked`'s own `userData` delivery is asserted
  correct against a known marker address (the regression check for the
  real bug fixed this round - see above); `GuiCheckBoxConnectToggled`/
  `GuiRadioButtonSetGroup`/`GuiComboBoxConnectChanged` (Round 4) all
  round-trip/fire correctly via `g_signal_emit_by_name`; and
  `GuiProgressBarSetRange`/`SetValue`/`GetValue` and
  `GuiSliderSetRange`/`SetValue`/`GetValue`/`ConnectValueChanged`
  (Round 5) round-trip correctly, including a second `userData`
  delivery regression check on the reused trampoline; and
  `GuiListBoxAddItem`/`GetItemText`/`GetCount`/`Clear`/
  `GetSelectedIndex`/`SetSelectedIndex` and `GuiTextViewSetText`/
  `GetText`/`SetEditable` (Round 6) round-trip correctly, including a
  third `userData` delivery regression check on the NEW dedicated
  3-arg `"row-selected"` trampoline (triggered via a genuine
  `GuiListBoxSetSelectedIndex` call, not a faked signal emission, so
  the real 3-argument signal shape is actually exercised); and
  `GuiWidgetSetPreferredSize` (Round 7) runs without crashing (a
  documented no-op on this backend - see above).
- `examples/widgets_form` - a `GuiBox` containing a `GuiLabel` +
  `GuiEntry` + `GuiButton`, clicking the button reads the entry and
  updates the label (confirmed launches and runs without crashing on
  this host; this session's own screenshot tooling wasn't available
  for a live capture here, unlike the Haiku-hosted examples elsewhere
  in this ecosystem - `examples/verify`'s own headless checks above are
  the primary verification for this round).

## See also

- [`eb-gui`](https://github.com/yann64/eb-gui) - the shared contract this package implements.
- [`eb-gui-qt6`](https://github.com/yann64/eb-gui-qt6) - the Qt6 adapter.
- [`eb-gtk4`](https://github.com/yann64/eb-gtk4) - the underlying GTK4 binding.
