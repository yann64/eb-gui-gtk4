' Idiomatic layer: eb-gui's Application/Window contract, implemented over
' eb-gtk4.
'
' `GuiApplication.handle`/`GuiWindow.handle` are the exact same GObj PTR
' eb-gtk4's own Application/Window TYPEs wrap - this adapter just copies
' that field across the two TYPE shapes at each call (a cheap 8-byte
' pointer copy, not a real conversion), never allocating a second handle
' of its own.

#include "gui.iface.bas"
#include "gtk4.iface.bas"

Extern "C" Lib "gio-2.0"
    ' CONFIRMED (by direct reproduction, not assumed): a segfault
    ' results from constructing/presenting a GtkApplicationWindow before
    ' the owning GApplication has been registered - real GTK4/eb-gtk4's
    ' own documented idiom always defers window construction to an
    ' "activate" signal handler, which registers the app as a side
    ' effect of ApplicationRun's own startup. eb-gui's own contract lets
    ' application code create/show windows synchronously, immediately
    ' after NewGuiApplication, with no activate handler at all - so this
    ' adapter registers eagerly (g_application_register is safe to call
    ' more than once; a no-op if already registered) to make that safe.
    Declare Function g_application_register(ByVal application AS GObj PTR, ByVal cancellable AS ANY PTR, ByVal error_out AS ANY PTR) AS INTEGER
End Extern

Extern "C" Lib "ebguigtk4"
    Declare Sub eb_gui_gtk4_window_set_close_callback(ByVal window AS ANY PTR, ByVal cb AS ANY PTR, ByVal userData AS ANY PTR)
    Declare Sub eb_gui_gtk4_action_connect_triggered(ByVal action AS ANY PTR, ByVal cb AS ANY PTR, ByVal userData AS ANY PTR)
    ' Generic bridge for every plain SUB(userData AS ANY PTR)-shaped
    ' contract signal - see shim_userdatasignal.h's own top comment for
    ' why a direct ObjConnect pass-through silently delivers the WRONG
    ' value (GTK4's real signal shape is (instance, user_data), and a
    ' 1-param eBasic handler binds its own param to instance, not
    ' user_data - confirmed by direct reproduction, not assumed).
    Declare Sub eb_gui_gtk4_connect_userdata_signal(ByVal obj AS ANY PTR, ByVal signalName AS ZSTRING, ByVal cb AS ANY PTR, ByVal userData AS ANY PTR)
    ' Dedicated bridge for GtkListBox's own "row-selected" signal - its
    ' real shape is (GtkListBox*, GtkListBoxRow*, gpointer), THREE real
    ' arguments, not two, so the generic 2-arg trampoline above cannot
    ' safely be reused (see shim_listboxselection.h's own top comment,
    ' and this round's own standalone spike that verified it before this
    ' declare was ever wired into GuiListBoxConnectSelectionChanged).
    Declare Sub eb_gui_gtk4_listbox_connect_selection_changed(ByVal listBox AS ANY PTR, ByVal cb AS ANY PTR, ByVal userData AS ANY PTR)
End Extern

''' Small per-adapter association table (handle -> handle) - makes up
''' for two gaps in what eb-gtk4's own public iface.bas exposes: (1)
''' g_object_get_data/set_data are raw-layer-only, not exported across
''' a --lib boundary, so this adapter can't tag a GTK4 handle with its
''' own data the way eb-gtk4 itself does internally for
''' WindowContentBox/WindowMenuBar/WindowToolBar; and (2)
''' GuiWindowStatusBar needs its own auto-created-once memory, since
''' (unlike WindowMenuBar/WindowToolBar) it's this adapter's OWN
''' composition on top of eb-gtk4's public API, not something eb-gtk4
''' tracks on its behalf. Two uses below: recording which window a
''' Menu/ToolBar belongs to (so GuiMenuAddAction/GuiToolBarAddAction
''' know which window's action map to register a fresh Action on), and
''' recording a window's own already-created StatusBar. A linear scan
''' over a small, fixed-size array - completely adequate for the
''' handful of windows/menus/tool bars a real application creates.
DIM ebGuiGtk4AssocKeys(128) AS ANY PTR
DIM ebGuiGtk4AssocVals(128) AS ANY PTR
DIM ebGuiGtk4AssocCount AS INTEGER

SUB EbGuiGtk4AssocSet(key AS ANY PTR, val AS ANY PTR)
    ebGuiGtk4AssocKeys(ebGuiGtk4AssocCount) = key
    ebGuiGtk4AssocVals(ebGuiGtk4AssocCount) = val
    ebGuiGtk4AssocCount = ebGuiGtk4AssocCount + 1
END SUB

FUNCTION EbGuiGtk4AssocGet(key AS ANY PTR) AS ANY PTR
    DIM i AS INTEGER
    FOR i = 0 TO ebGuiGtk4AssocCount - 1
        IF ebGuiGtk4AssocKeys(i) = key THEN
            EbGuiGtk4AssocGet = ebGuiGtk4AssocVals(i)
            EXIT FUNCTION
        END IF
    NEXT i
    EbGuiGtk4AssocGet = 0
END FUNCTION

DIM ebGuiGtk4ActionCounter AS INTEGER

FUNCTION NewGuiApplication(appId AS ZSTRING) AS GuiApplication
    DIM realApp AS Application
    realApp = NewApplication(appId)
    CALL g_application_register(realApp.handle, 0, 0)
    DIM result AS GuiApplication
    result.handle = realApp.handle
    NewGuiApplication = result
END FUNCTION

FUNCTION GuiApplicationRun(app AS GuiApplication) AS INTEGER
    DIM realApp AS Application
    realApp.handle = app.handle
    GuiApplicationRun = ApplicationRun(realApp)
END FUNCTION

SUB GuiApplicationQuit(app AS GuiApplication)
    DIM realApp AS Application
    realApp.handle = app.handle
    CALL ApplicationQuit(realApp)
END SUB

''' Always created as a real GtkApplicationWindow (tied to `app`, so
''' GTK4's own GApplication window tracking gives GuiApplicationRun its
''' "return when the last window closes" behavior for free - see this
''' package's README "Ownership and the quit model").
FUNCTION NewGuiWindow(app AS GuiApplication, title AS ZSTRING, width AS INTEGER, height AS INTEGER) AS GuiWindow
    DIM realApp AS Application
    realApp.handle = app.handle
    DIM win AS Window
    win = NewApplicationWindow(realApp)
    CALL WindowSetTitle(win, title)
    CALL WindowSetDefaultSize(win, width, height)
    DIM result AS GuiWindow
    result.handle = win.handle
    NewGuiWindow = result
END FUNCTION

SUB GuiWindowSetTitle(win AS GuiWindow, title AS ZSTRING)
    DIM realWin AS Window
    realWin.handle = win.handle
    CALL WindowSetTitle(realWin, title)
END SUB

''' Real GTK4 has no separate "show" from "present" for a top-level
''' window - WindowPresent both shows and raises it.
SUB GuiWindowShow(win AS GuiWindow)
    DIM realWin AS Window
    realWin.handle = win.handle
    CALL WindowPresent(realWin)
END SUB

SUB GuiWindowHide(win AS GuiWindow)
    DIM realWidget AS Widget
    realWidget.handle = win.handle
    CALL WidgetSetVisible(realWidget, 0)
END SUB

''' GTK4 has no window-level "disabled" concept of its own - this
''' desensitizes the window's own top-level widget, which (real GTK4
''' behavior) transitively desensitizes every child too.
SUB GuiWindowSetEnabled(win AS GuiWindow, enabled AS INTEGER)
    DIM realWidget AS Widget
    realWidget.handle = win.handle
    CALL WidgetSetEnabled(realWidget, enabled)
END SUB

FUNCTION GuiWindowIsEnabled(win AS GuiWindow) AS INTEGER
    DIM realWidget AS Widget
    realWidget.handle = win.handle
    GuiWindowIsEnabled = WidgetIsEnabled(realWidget)
END FUNCTION

''' Always 0 on this backend - GTK4 itself removed programmatic window
''' positioning upstream (Wayland/CSD make it largely meaningless), not
''' a gap in eb-gtk4's own binding.
FUNCTION GuiWindowCanMove() AS INTEGER
    GuiWindowCanMove = 0
END FUNCTION

''' Best-effort no-op on this backend - see GuiWindowCanMove.
SUB GuiWindowMove(win AS GuiWindow, x AS INTEGER, y AS INTEGER)
END SUB

SUB GuiWindowResize(win AS GuiWindow, width AS INTEGER, height AS INTEGER)
    DIM realWin AS Window
    realWin.handle = win.handle
    CALL WindowSetDefaultSize(realWin, width, height)
END SUB

SUB GuiWindowSetModal(win AS GuiWindow, parent AS GuiWindow)
    DIM realWin AS Window
    realWin.handle = win.handle
    DIM realParent AS Window
    realParent.handle = parent.handle
    CALL WindowSetModal(realWin, realParent)
END SUB

SUB GuiWindowClearModal(win AS GuiWindow)
    DIM realWin AS Window
    realWin.handle = win.handle
    CALL WindowClearModal(realWin)
END SUB

''' `handler` is `FUNCTION(userData AS ANY PTR) AS INTEGER`, nonzero =
''' allow the close - bridged to GTK4's real "close-request" signal
''' (opposite polarity, different signature) by this package's own tiny
''' native trampoline (native/shim_closecallback.h - eBasic itself has
''' no way to call through an arbitrary stored function pointer, only
''' native code can).
SUB GuiWindowSetCloseCallback(win AS GuiWindow, handler AS ANY PTR, userData AS ANY PTR)
    CALL eb_gui_gtk4_window_set_close_callback(win.handle, handler, userData)
END SUB

''' Only meaningful for a window never Run/shown - see this package's
''' README "Ownership and the quit model".
SUB GuiWindowDestroy(win AS GuiWindow)
    DIM realWin AS Window
    realWin.handle = win.handle
    CALL WindowDestroy(realWin)
END SUB

''' Real GtkStatusbar is auto-created and owned by no particular
''' window - this adapter creates one and packs it into the window's
''' own shared content box (WindowContentBox, eb-gtk4 v0.11.0+) the
''' first time it's requested, matching GuiWindowStatusBar's
''' "auto-created, one per window" contract; a second call for the same
''' window returns the same StatusBar rather than creating another
''' (tracked via this adapter's own association table, since - unlike
''' WindowMenuBar/WindowToolBar - eb-gtk4 has no built-in memory of
''' "the" status bar for a window). Composes correctly with
''' GuiWindowMenuBar/GuiWindowToolBar regardless of call order, since
''' all three now share the same underlying content box.
FUNCTION GuiWindowStatusBar(win AS GuiWindow) AS GuiStatusBar
    DIM existing AS ANY PTR
    existing = EbGuiGtk4AssocGet(win.handle)
    IF existing <> 0 THEN
        DIM existingResult AS GuiStatusBar
        existingResult.handle = existing
        GuiWindowStatusBar = existingResult
        EXIT FUNCTION
    END IF
    DIM realWin AS Window
    realWin.handle = win.handle
    DIM sb AS StatusBar
    sb = NewStatusBar()
    DIM contentBox AS Box
    contentBox = WindowContentBox(realWin)
    CALL BoxAppend(contentBox, sb)
    CALL EbGuiGtk4AssocSet(win.handle, sb.handle)
    DIM result AS GuiStatusBar
    result.handle = sb.handle
    GuiWindowStatusBar = result
END FUNCTION

SUB GuiStatusBarShowMessage(sb AS GuiStatusBar, text AS ZSTRING)
    DIM realSb AS StatusBar
    realSb.handle = sb.handle
    CALL StatusBarShowMessage(realSb, text)
END SUB

SUB GuiStatusBarClear(sb AS GuiStatusBar)
    DIM realSb AS StatusBar
    realSb.handle = sb.handle
    CALL StatusBarClear(realSb)
END SUB

''' `parent` is accepted (for signature parity with the Qt6 adapter,
''' where it's required) but ignored - this backend's own GtkTimer
''' isn't a GObject at all and has no parent/ownership concept.
FUNCTION NewGuiTimer(parent AS GuiWindow) AS GuiTimer
    DIM t AS GtkTimer
    t = NewGtkTimer()
    DIM result AS GuiTimer
    result.handle = t.handle
    NewGuiTimer = result
END FUNCTION

SUB GuiTimerSetInterval(t AS GuiTimer, milliseconds AS INTEGER)
    DIM realT AS GtkTimer
    realT.handle = t.handle
    CALL GtkTimerSetInterval(realT, milliseconds)
END SUB

SUB GuiTimerSetSingleShot(t AS GuiTimer, singleShot AS INTEGER)
    DIM realT AS GtkTimer
    realT.handle = t.handle
    CALL GtkTimerSetSingleShot(realT, singleShot)
END SUB

SUB GuiTimerConnectTimeout(t AS GuiTimer, handler AS ANY PTR, userData AS ANY PTR)
    DIM realT AS GtkTimer
    realT.handle = t.handle
    CALL GtkTimerConnectTimeout(realT, handler, userData)
END SUB

SUB GuiTimerStart(t AS GuiTimer)
    DIM realT AS GtkTimer
    realT.handle = t.handle
    CALL GtkTimerStart(realT)
END SUB

SUB GuiTimerStop(t AS GuiTimer)
    DIM realT AS GtkTimer
    realT.handle = t.handle
    CALL GtkTimerStop(realT)
END SUB

FUNCTION GuiTimerIsActive(t AS GuiTimer) AS INTEGER
    DIM realT AS GtkTimer
    realT.handle = t.handle
    GuiTimerIsActive = GtkTimerIsActive(realT)
END FUNCTION

''' Meaningful on this backend - frees the timer's own plain heap
''' allocation (not a GObject, so nothing else would free it).
SUB GuiTimerDestroy(t AS GuiTimer)
    DIM realT AS GtkTimer
    realT.handle = t.handle
    CALL GtkTimerDestroy(realT)
END SUB

''' Auto-created and installed at the top of the window's shared
''' content box the first time this is called for `win` - eb-gtk4's own
''' WindowMenuBar (v0.11.0+) already tracks this internally, so no use
''' of this adapter's own association table is needed here.
FUNCTION GuiWindowMenuBar(win AS GuiWindow) AS GuiMenuBar
    DIM realWin AS Window
    realWin.handle = win.handle
    DIM bar AS MenuBar
    bar = WindowMenuBar(realWin)
    CALL EbGuiGtk4AssocSet(bar.handle, win.handle)
    DIM result AS GuiMenuBar
    result.handle = bar.handle
    GuiWindowMenuBar = result
END FUNCTION

FUNCTION GuiMenuBarAddMenu(bar AS GuiMenuBar, title AS ZSTRING) AS GuiMenu
    DIM realBar AS MenuBar
    realBar.handle = bar.handle
    DIM m AS Menu
    m = MenuBarAddMenu(realBar, title)
    DIM winHandle AS ANY PTR
    winHandle = EbGuiGtk4AssocGet(bar.handle)
    CALL EbGuiGtk4AssocSet(m.handle, winHandle)
    DIM result AS GuiMenu
    result.handle = m.handle
    GuiMenuBarAddMenu = result
END FUNCTION

''' Real GTK4 actions (GSimpleAction) are shareable, window-scoped
''' objects independent of any menu - this contract instead follows
''' Qt6's simpler "create fresh per call" shape (see eb-gui's own
''' README), so a brand-new, uniquely-named Action is registered on
''' `guiMenu`'s owning window (tracked via this adapter's association
''' table, since GTK4's own action map needs a real Window, not just a
''' Menu) every time this is called.
FUNCTION GuiMenuAddAction(guiMenu AS GuiMenu, text AS ZSTRING) AS GuiAction
    DIM winHandle AS ANY PTR
    winHandle = EbGuiGtk4AssocGet(guiMenu.handle)
    DIM realWin AS Window
    realWin.handle = winHandle
    ebGuiGtk4ActionCounter = ebGuiGtk4ActionCounter + 1
    DIM act AS Action
    act = NewAction(realWin, "eb_gui_action_" & Str(ebGuiGtk4ActionCounter))
    DIM realMenu AS Menu
    realMenu.handle = guiMenu.handle
    CALL MenuAddAction(realMenu, act, text)
    DIM result AS GuiAction
    result.handle = act.handle
    GuiMenuAddAction = result
END FUNCTION

''' Bridged to GTK4's real GSimpleAction "activate" signal (different
''' argument shape) by this package's own native trampoline - see
''' native/shim_actiontrigger.h.
SUB GuiActionConnectTriggered(a AS GuiAction, handler AS ANY PTR, userData AS ANY PTR)
    CALL eb_gui_gtk4_action_connect_triggered(a.handle, handler, userData)
END SUB

SUB GuiActionSetEnabled(a AS GuiAction, enabled AS INTEGER)
    DIM realAction AS Action
    realAction.handle = a.handle
    CALL ActionSetEnabled(realAction, enabled)
END SUB

''' Not bound at all on this backend's own Action (eb-gtk4 has no
''' ActionIsEnabled) - always reports enabled, since GSimpleAction
''' defaults to enabled and this adapter never disables one on its own.
FUNCTION GuiActionIsEnabled(a AS GuiAction) AS INTEGER
    GuiActionIsEnabled = 1
END FUNCTION

SUB GuiActionTrigger(a AS GuiAction)
    DIM realAction AS Action
    realAction.handle = a.handle
    CALL ActionActivate(realAction)
END SUB

''' Auto-created (an empty Box of Buttons, see eb-gtk4's own toolbar.bas
''' top comment) and installed into the window's shared content box the
''' first time this is called for `win` - eb-gtk4's own WindowToolBar
''' (v0.11.0+) already tracks this internally, so no use of this
''' adapter's own association table is needed here.
FUNCTION GuiWindowToolBar(win AS GuiWindow) AS GuiToolBar
    DIM realWin AS Window
    realWin.handle = win.handle
    DIM tb AS ToolBar
    tb = WindowToolBar(realWin)
    CALL EbGuiGtk4AssocSet(tb.handle, win.handle)
    DIM result AS GuiToolBar
    result.handle = tb.handle
    GuiWindowToolBar = result
END FUNCTION

''' Real GTK4 tool bars (see eb-gtk4's own toolbar.bas) are plain
''' Buttons, not Actions - this adapter bridges the gap by creating a
''' real window-scoped Action alongside the button (same
''' "create fresh per call" shape GuiMenuAddAction uses) and forwarding
''' the button's own "clicked" signal into the action's "activate", so
''' the returned GuiAction behaves identically whether it came from a
''' menu or a tool bar.
FUNCTION GuiToolBarAddAction(bar AS GuiToolBar, text AS ZSTRING) AS GuiAction
    DIM winHandle AS ANY PTR
    winHandle = EbGuiGtk4AssocGet(bar.handle)
    DIM realWin AS Window
    realWin.handle = winHandle
    ebGuiGtk4ActionCounter = ebGuiGtk4ActionCounter + 1
    DIM act AS Action
    act = NewAction(realWin, "eb_gui_action_" & Str(ebGuiGtk4ActionCounter))
    DIM realBar AS ToolBar
    realBar.handle = bar.handle
    DIM btn AS Button
    btn = ToolBarAddButton(realBar, text)
    CALL ObjConnect(btn, "clicked", @EbGuiGtk4ToolbarButtonClicked, act.handle)
    DIM result AS GuiAction
    result.handle = act.handle
    GuiToolBarAddAction = result
END FUNCTION

''' Fixed, single, reusable forwarding handler for GuiToolBarAddAction -
''' the per-instance data is `userData` (the paired Action's own
''' handle), the standard callback-with-userData trampoling pattern
''' this whole ecosystem already relies on (eBasic itself has no way to
''' dynamically generate a distinct callback per call).
SUB EbGuiGtk4ToolbarButtonClicked(btn AS GObj PTR, userData AS ANY PTR)
    DIM act AS Action
    act.handle = userData
    CALL ActionActivate(act)
END SUB

FUNCTION NewGuiButton(text AS ZSTRING) AS GuiButton
    DIM realBtn AS Button
    realBtn = NewButton(text)
    DIM result AS GuiButton
    result.handle = realBtn.handle
    NewGuiButton = result
END FUNCTION

SUB GuiButtonSetText(b AS GuiButton, text AS ZSTRING)
    DIM realBtn AS Button
    realBtn.handle = b.handle
    CALL ButtonSetLabel(realBtn, text)
END SUB

FUNCTION GuiButtonGetText(b AS GuiButton) AS ZSTRING
    DIM realBtn AS Button
    realBtn.handle = b.handle
    GuiButtonGetText = ButtonGetLabel(realBtn)
END FUNCTION

''' Real bug fixed this round: a direct ObjConnect(..., "clicked", ...)
''' pass-through silently delivered the wrong value to the contract's
''' own 1-param handler shape (GTK4's real "clicked" signal is
''' (GtkButton*, gpointer) - the handler's own sole parameter bound to
''' the button itself, not the real userData). Fixed via the generic
''' eb_gui_gtk4_connect_userdata_signal trampoline (see its own header
''' comment) - same reasoning as this package's existing
''' GuiActionConnectTriggered bridge.
SUB GuiButtonConnectClicked(b AS GuiButton, handler AS ANY PTR, userData AS ANY PTR)
    CALL eb_gui_gtk4_connect_userdata_signal(b.handle, "clicked", handler, userData)
END SUB

FUNCTION NewGuiLabel(text AS ZSTRING) AS GuiLabel
    DIM realLbl AS Label
    realLbl = NewLabel(text)
    DIM result AS GuiLabel
    result.handle = realLbl.handle
    NewGuiLabel = result
END FUNCTION

SUB GuiLabelSetText(l AS GuiLabel, text AS ZSTRING)
    DIM realLbl AS Label
    realLbl.handle = l.handle
    CALL LabelSetText(realLbl, text)
END SUB

FUNCTION NewGuiEntry(text AS ZSTRING) AS GuiEntry
    DIM realEntry AS Entry
    realEntry = NewEntry()
    CALL EntrySetText(realEntry, text)
    DIM result AS GuiEntry
    result.handle = realEntry.handle
    NewGuiEntry = result
END FUNCTION

SUB GuiEntrySetText(e AS GuiEntry, text AS ZSTRING)
    DIM realEntry AS Entry
    realEntry.handle = e.handle
    CALL EntrySetText(realEntry, text)
END SUB

FUNCTION GuiEntryGetText(e AS GuiEntry) AS ZSTRING
    DIM realEntry AS Entry
    realEntry.handle = e.handle
    GuiEntryGetText = EntryGetText(realEntry)
END FUNCTION

''' Real GtkEditable (which Entry implements) emits a real "changed"
''' signal on every text modification - bridged via the same
''' eb_gui_gtk4_connect_userdata_signal trampoline GuiButtonConnectClicked
''' uses (see its own doc comment for why a plain ObjConnect
''' pass-through was wrong).
SUB GuiEntryConnectChanged(e AS GuiEntry, handler AS ANY PTR, userData AS ANY PTR)
    CALL eb_gui_gtk4_connect_userdata_signal(e.handle, "changed", handler, userData)
END SUB

''' `orientation` (0=horizontal, 1=vertical) matches GTK4's own
''' GTK_ORIENTATION_HORIZONTAL/VERTICAL values exactly - passed straight
''' through, no translation needed.
FUNCTION NewGuiBox(orientation AS INTEGER, spacing AS INTEGER) AS GuiBox
    DIM realBox AS Box
    realBox = NewBox(orientation, spacing)
    DIM result AS GuiBox
    result.handle = realBox.handle
    NewGuiBox = result
END FUNCTION

''' A real GTK4 `Box`/`Grid` is itself a `Widget`, so `child` may be any
''' other `Gui*` TYPE's own handle - including another `GuiBox`/
''' `GuiGrid`, which nest directly with no holder widget needed (unlike
''' `eb-gui-qt6`/`eb-gui-haiku` - see `eb-gui`'s own README).
SUB GuiBoxAddChild(bx AS GuiBox, child AS ANY PTR)
    DIM realBox AS Box
    realBox.handle = bx.handle
    DIM childWidget AS Widget
    childWidget.handle = child
    CALL BoxAppend(realBox, childWidget)
END SUB

FUNCTION NewGuiGrid() AS GuiGrid
    DIM realGrid AS Grid
    realGrid = NewGrid()
    DIM result AS GuiGrid
    result.handle = realGrid.handle
    NewGuiGrid = result
END FUNCTION

SUB GuiGridAttach(gr AS GuiGrid, child AS ANY PTR, column AS INTEGER, row AS INTEGER, columnSpan AS INTEGER, rowSpan AS INTEGER)
    DIM realGrid AS Grid
    realGrid.handle = gr.handle
    DIM childWidget AS Widget
    childWidget.handle = child
    CALL GridAttach(realGrid, childWidget, column, row, columnSpan, rowSpan)
END SUB

''' Maps the contract's toolkit-neutral GUI_ALIGN_* to real GTK4's own
''' GTK_ALIGN_* values - NOT the same numbering (GUI_ALIGN_CENTER=2/
''' GUI_ALIGN_END=3 vs. real GTK_ALIGN_END=2/GTK_ALIGN_CENTER=3).
FUNCTION EbGuiGtk4MapAlign(guiAlign AS INTEGER) AS INTEGER
    IF guiAlign = GUI_ALIGN_START THEN
        EbGuiGtk4MapAlign = GTK_ALIGN_START
    ELSEIF guiAlign = GUI_ALIGN_CENTER THEN
        EbGuiGtk4MapAlign = GTK_ALIGN_CENTER
    ELSEIF guiAlign = GUI_ALIGN_END THEN
        EbGuiGtk4MapAlign = GTK_ALIGN_END
    ELSE
        EbGuiGtk4MapAlign = GTK_ALIGN_FILL
    END IF
END FUNCTION

''' GTK4 puts expand/alignment on the CHILD widget itself, not the
''' Box - set them, then append exactly like GuiBoxAddChild. `expand`
''' is applied along BOTH axes (hexpand and vexpand) since the
''' contract doesn't know the box's own orientation at this call site;
''' the cross-axis expand is harmless (a Box only actually stretches
''' children along its own main axis regardless of the child's own
''' vexpand/hexpand on the other axis).
SUB GuiBoxAddChildEx(bx AS GuiBox, child AS ANY PTR, expand AS SINGLE, halign AS INTEGER, valign AS INTEGER)
    DIM childWidget AS Widget
    childWidget.handle = child
    DIM doExpand AS INTEGER
    doExpand = 0
    IF expand <> 0 THEN
        doExpand = 1
    END IF
    CALL WidgetSetHExpand(childWidget, doExpand)
    CALL WidgetSetVExpand(childWidget, doExpand)
    CALL WidgetSetHAlign(childWidget, EbGuiGtk4MapAlign(halign))
    CALL WidgetSetVAlign(childWidget, EbGuiGtk4MapAlign(valign))
    CALL GuiBoxAddChild(bx, child)
END SUB

SUB GuiGridAttachEx(gr AS GuiGrid, child AS ANY PTR, column AS INTEGER, row AS INTEGER, columnSpan AS INTEGER, rowSpan AS INTEGER, halign AS INTEGER, valign AS INTEGER)
    DIM childWidget AS Widget
    childWidget.handle = child
    CALL WidgetSetHAlign(childWidget, EbGuiGtk4MapAlign(halign))
    CALL WidgetSetVAlign(childWidget, EbGuiGtk4MapAlign(valign))
    CALL GuiGridAttach(gr, child, column, row, columnSpan, rowSpan)
END SUB

''' GtkGrid has no per-column/row weight concept in real GTK4 at all -
''' a real absence upstream, not a binding gap - so this is a
''' documented, accepted no-op on this backend (see eb-gui's own
''' README).
SUB GuiGridSetColumnWeight(gr AS GuiGrid, column AS INTEGER, weight AS SINGLE)
END SUB

SUB GuiGridSetRowWeight(gr AS GuiGrid, row AS INTEGER, weight AS SINGLE)
END SUB

''' Direct pass-through to gtk_widget_set_size_request - already real
''' and bound, no prerequisite native work needed this round.
SUB GuiWidgetSetMinSize(handle AS ANY PTR, width AS INTEGER, height AS INTEGER)
    DIM w AS Widget
    w.handle = handle
    CALL WidgetSetSizeRequest(w, width, height)
END SUB

''' A documented, accepted no-op - real GTK4 has no generic per-widget
''' maximum-size concept at all (confirmed absent upstream, not a
''' binding gap - see eb-gui's own README).
SUB GuiWidgetSetMaxSize(handle AS ANY PTR, width AS INTEGER, height AS INTEGER)
END SUB

''' Appends `content` into the window's existing `WindowContentBox` -
''' call after `GuiWindowMenuBar`/`GuiWindowToolBar` and before
''' `GuiWindowStatusBar` for the expected top-to-bottom visual order
''' (unenforced convention, matching this package's own existing
''' Menu/ToolBar/StatusBar ordering precedent).
SUB GuiWindowSetContent(win AS GuiWindow, content AS ANY PTR)
    DIM realWin AS Window
    realWin.handle = win.handle
    DIM contentBox AS Box
    contentBox = WindowContentBox(realWin)
    DIM childWidget AS Widget
    childWidget.handle = content
    CALL BoxAppend(contentBox, childWidget)
END SUB

''' Real GTK4 unifies checkbox/radio-button into ONE widget class,
''' CheckButton - GuiCheckBox and GuiRadioButton both wrap the exact
''' same underlying widget, the contract-level TYPE being the only
''' thing distinguishing their role (see eb-gui's own README).
FUNCTION NewGuiCheckBox(text AS ZSTRING) AS GuiCheckBox
    DIM realCb AS CheckButton
    realCb = NewCheckButton(text)
    DIM result AS GuiCheckBox
    result.handle = realCb.handle
    NewGuiCheckBox = result
END FUNCTION

SUB GuiCheckBoxSetChecked(cb AS GuiCheckBox, checked AS INTEGER)
    DIM realCb AS CheckButton
    realCb.handle = cb.handle
    CALL CheckButtonSetActive(realCb, checked)
END SUB

FUNCTION GuiCheckBoxIsChecked(cb AS GuiCheckBox) AS INTEGER
    DIM realCb AS CheckButton
    realCb.handle = cb.handle
    GuiCheckBoxIsChecked = CheckButtonGetActive(realCb)
END FUNCTION

SUB GuiCheckBoxConnectToggled(cb AS GuiCheckBox, handler AS ANY PTR, userData AS ANY PTR)
    CALL eb_gui_gtk4_connect_userdata_signal(cb.handle, "toggled", handler, userData)
END SUB

FUNCTION NewGuiRadioButton(text AS ZSTRING) AS GuiRadioButton
    DIM realCb AS CheckButton
    realCb = NewCheckButton(text)
    DIM result AS GuiRadioButton
    result.handle = realCb.handle
    NewGuiRadioButton = result
END FUNCTION

SUB GuiRadioButtonSetChecked(rb AS GuiRadioButton, checked AS INTEGER)
    DIM realCb AS CheckButton
    realCb.handle = rb.handle
    CALL CheckButtonSetActive(realCb, checked)
END SUB

FUNCTION GuiRadioButtonIsChecked(rb AS GuiRadioButton) AS INTEGER
    DIM realCb AS CheckButton
    realCb.handle = rb.handle
    GuiRadioButtonIsChecked = CheckButtonGetActive(realCb)
END FUNCTION

SUB GuiRadioButtonConnectToggled(rb AS GuiRadioButton, handler AS ANY PTR, userData AS ANY PTR)
    CALL eb_gui_gtk4_connect_userdata_signal(rb.handle, "toggled", handler, userData)
END SUB

''' Direct pass-through to gtk_check_button_set_group - real GTK4 has
''' no separate group object at all, a CheckButton is simply chained
''' directly to another one.
SUB GuiRadioButtonSetGroup(rb AS GuiRadioButton, firstInGroup AS GuiRadioButton)
    DIM realRb AS CheckButton
    realRb.handle = rb.handle
    DIM realFirst AS CheckButton
    realFirst.handle = firstInGroup.handle
    CALL CheckButtonSetGroup(realRb, realFirst)
END SUB

FUNCTION NewGuiComboBox() AS GuiComboBox
    DIM realCombo AS ComboBoxText
    realCombo = NewComboBoxText()
    DIM result AS GuiComboBox
    result.handle = realCombo.handle
    NewGuiComboBox = result
END FUNCTION

SUB GuiComboBoxAddItem(cb AS GuiComboBox, text AS ZSTRING)
    DIM realCombo AS ComboBoxText
    realCombo.handle = cb.handle
    CALL ComboBoxTextAppendText(realCombo, text)
END SUB

FUNCTION GuiComboBoxGetSelectedIndex(cb AS GuiComboBox) AS INTEGER
    DIM realCombo AS ComboBoxText
    realCombo.handle = cb.handle
    GuiComboBoxGetSelectedIndex = ComboBoxTextGetActive(realCombo)
END FUNCTION

SUB GuiComboBoxSetSelectedIndex(cb AS GuiComboBox, index AS INTEGER)
    DIM realCombo AS ComboBoxText
    realCombo.handle = cb.handle
    CALL ComboBoxTextSetActive(realCombo, index)
END SUB

''' Real gtk_combo_box_text_get_active_text returns a newly `g_malloc`'d
''' string - the contract has no matching free function, so (matching
''' eb-gui-qt6's own identical GuiButtonGetText precedent) this
''' deliberately accepts and documents a small per-call leak rather
''' than redesigning the contract or risking a dangling pointer.
FUNCTION GuiComboBoxGetSelectedText(cb AS GuiComboBox) AS ZSTRING
    DIM realCombo AS ComboBoxText
    realCombo.handle = cb.handle
    DIM raw AS ANY PTR
    raw = ComboBoxTextGetActiveText(realCombo)
    DIM z AS ZSTRING
    z = raw
    GuiComboBoxGetSelectedText = z
END FUNCTION

SUB GuiComboBoxConnectChanged(cb AS GuiComboBox, handler AS ANY PTR, userData AS ANY PTR)
    CALL eb_gui_gtk4_connect_userdata_signal(cb.handle, "changed", handler, userData)
END SUB

''' Real GTK4 has no integer min/max/value model for GtkProgressBar at
''' all - just a 0.0-1.0 fraction. This adapter tracks each progress
''' bar's own (min, max, value) itself so GetValue can return the
''' tracked integer directly rather than re-deriving a lossy one back
''' from the fraction.
DIM ebGuiGtk4ProgressBarKeys(64) AS ANY PTR
DIM ebGuiGtk4ProgressBarMins(64) AS INTEGER
DIM ebGuiGtk4ProgressBarMaxs(64) AS INTEGER
DIM ebGuiGtk4ProgressBarValues(64) AS INTEGER
DIM ebGuiGtk4ProgressBarCount AS INTEGER

FUNCTION EbGuiGtk4ProgressBarFindIndex(handle AS ANY PTR) AS INTEGER
    DIM i AS INTEGER
    FOR i = 0 TO ebGuiGtk4ProgressBarCount - 1
        IF ebGuiGtk4ProgressBarKeys(i) = handle THEN
            EbGuiGtk4ProgressBarFindIndex = i
            EXIT FUNCTION
        END IF
    NEXT i
    EbGuiGtk4ProgressBarFindIndex = -1
END FUNCTION

FUNCTION NewGuiProgressBar() AS GuiProgressBar
    DIM realPb AS ProgressBar
    realPb = NewProgressBar()
    ebGuiGtk4ProgressBarKeys(ebGuiGtk4ProgressBarCount) = realPb.handle
    ebGuiGtk4ProgressBarMins(ebGuiGtk4ProgressBarCount) = 0
    ebGuiGtk4ProgressBarMaxs(ebGuiGtk4ProgressBarCount) = 100
    ebGuiGtk4ProgressBarValues(ebGuiGtk4ProgressBarCount) = 0
    ebGuiGtk4ProgressBarCount = ebGuiGtk4ProgressBarCount + 1
    DIM result AS GuiProgressBar
    result.handle = realPb.handle
    NewGuiProgressBar = result
END FUNCTION

SUB GuiProgressBarSetRange(pb AS GuiProgressBar, min AS INTEGER, max AS INTEGER)
    DIM i AS INTEGER
    i = EbGuiGtk4ProgressBarFindIndex(pb.handle)
    ebGuiGtk4ProgressBarMins(i) = min
    ebGuiGtk4ProgressBarMaxs(i) = max
END SUB

FUNCTION GuiProgressBarGetValue(pb AS GuiProgressBar) AS INTEGER
    DIM i AS INTEGER
    i = EbGuiGtk4ProgressBarFindIndex(pb.handle)
    GuiProgressBarGetValue = ebGuiGtk4ProgressBarValues(i)
END FUNCTION

SUB GuiProgressBarSetValue(pb AS GuiProgressBar, value AS INTEGER)
    DIM i AS INTEGER
    i = EbGuiGtk4ProgressBarFindIndex(pb.handle)
    ebGuiGtk4ProgressBarValues(i) = value
    DIM realPb AS ProgressBar
    realPb.handle = pb.handle
    DIM minV AS INTEGER
    DIM maxV AS INTEGER
    minV = ebGuiGtk4ProgressBarMins(i)
    maxV = ebGuiGtk4ProgressBarMaxs(i)
    DIM fraction AS DOUBLE
    IF maxV > minV THEN
        fraction = CDbl(value - minV) / CDbl(maxV - minV)
    ELSE
        fraction = 0.0
    END IF
    CALL ProgressBarSetFraction(realPb, fraction)
END SUB

FUNCTION NewGuiSlider(orientation AS INTEGER) AS GuiSlider
    DIM realScale AS Scale
    realScale = NewScale(orientation, 0.0, 100.0, 1.0)
    DIM result AS GuiSlider
    result.handle = realScale.handle
    NewGuiSlider = result
END FUNCTION

SUB GuiSliderSetRange(s AS GuiSlider, min AS INTEGER, max AS INTEGER)
    DIM realScale AS Scale
    realScale.handle = s.handle
    CALL ScaleSetRange(realScale, min, max)
END SUB

FUNCTION GuiSliderGetValue(s AS GuiSlider) AS INTEGER
    DIM realScale AS Scale
    realScale.handle = s.handle
    GuiSliderGetValue = ScaleGetValue(realScale)
END FUNCTION

SUB GuiSliderSetValue(s AS GuiSlider, value AS INTEGER)
    DIM realScale AS Scale
    realScale.handle = s.handle
    CALL ScaleSetValue(realScale, value)
END SUB

''' Reuses the same Round 4 trampoline already fixed to correctly
''' deliver only `userData` - real GtkRange's own "value-changed"
''' signal has the identical (instance, user_data) shape as
''' "clicked"/"changed"/"toggled".
SUB GuiSliderConnectValueChanged(s AS GuiSlider, handler AS ANY PTR, userData AS ANY PTR)
    CALL eb_gui_gtk4_connect_userdata_signal(s.handle, "value-changed", handler, userData)
END SUB

FUNCTION NewGuiListBox() AS GuiListBox
    DIM realBox AS ListBox
    realBox = NewListBox()
    DIM result AS GuiListBox
    result.handle = realBox.handle
    NewGuiListBox = result
END FUNCTION

''' Wraps `text` in a plain Label and appends it as a new row - real
''' GtkListBox auto-wraps every appended widget in its own row.
SUB GuiListBoxAddItem(lb AS GuiListBox, text AS ZSTRING)
    DIM realBox AS ListBox
    realBox.handle = lb.handle
    DIM lbl AS Label
    lbl = NewLabel(text)
    CALL ListBoxAppend(realBox, lbl)
END SUB

''' Reads a row's own appended Label back via ListBoxRowGetChild - no
''' internal item-tracking table needed, unlike GuiComboBox (real
''' GtkComboBoxText's underlying item has no such getter).
FUNCTION GuiListBoxGetItemText(lb AS GuiListBox, index AS INTEGER) AS ZSTRING
    DIM realBox AS ListBox
    realBox.handle = lb.handle
    DIM row AS ListBoxRow
    row = ListBoxGetRowAtIndex(realBox, index)
    DIM child AS Widget
    child = ListBoxRowGetChild(row)
    DIM lbl AS Label
    lbl.handle = child.handle
    GuiListBoxGetItemText = LabelGetText(lbl)
END FUNCTION

FUNCTION GuiListBoxGetCount(lb AS GuiListBox) AS INTEGER
    DIM realBox AS ListBox
    realBox.handle = lb.handle
    DIM count AS INTEGER
    DIM row AS ListBoxRow
    count = 0
    row = ListBoxGetRowAtIndex(realBox, count)
    DO WHILE row.handle <> 0
        count = count + 1
        row = ListBoxGetRowAtIndex(realBox, count)
    LOOP
    GuiListBoxGetCount = count
END FUNCTION

SUB GuiListBoxClear(lb AS GuiListBox)
    DIM realBox AS ListBox
    realBox.handle = lb.handle
    CALL ListBoxRemoveAll(realBox)
END SUB

''' -1 if nothing selected - real GTK4 returns NULL from
''' gtk_list_box_get_selected_row in that case.
FUNCTION GuiListBoxGetSelectedIndex(lb AS GuiListBox) AS INTEGER
    DIM realBox AS ListBox
    realBox.handle = lb.handle
    DIM row AS ListBoxRow
    row = ListBoxGetSelectedRow(realBox)
    IF row.handle = 0 THEN
        GuiListBoxGetSelectedIndex = -1
    ELSE
        GuiListBoxGetSelectedIndex = ListBoxRowGetIndex(row)
    END IF
END FUNCTION

SUB GuiListBoxSetSelectedIndex(lb AS GuiListBox, index AS INTEGER)
    DIM realBox AS ListBox
    realBox.handle = lb.handle
    DIM row AS ListBoxRow
    row = ListBoxGetRowAtIndex(realBox, index)
    CALL ListBoxSelectRow(realBox, row)
END SUB

''' Uses the NEW dedicated 3-arg trampoline, not the generic Round 4
''' one - see shim_listboxselection.h's own top comment for why.
SUB GuiListBoxConnectSelectionChanged(lb AS GuiListBox, handler AS ANY PTR, userData AS ANY PTR)
    CALL eb_gui_gtk4_listbox_connect_selection_changed(lb.handle, handler, userData)
END SUB

FUNCTION NewGuiTextView() AS GuiTextView
    DIM realView AS TextView
    realView = NewTextView()
    DIM result AS GuiTextView
    result.handle = realView.handle
    NewGuiTextView = result
END FUNCTION

SUB GuiTextViewSetText(tv AS GuiTextView, text AS ZSTRING)
    DIM realView AS TextView
    realView.handle = tv.handle
    DIM buf AS TextBuffer
    buf = TextViewGetBuffer(realView)
    CALL TextBufferSetText(buf, text)
END SUB

''' Real gtk_text_buffer_get_text returns a newly `g_malloc`'d string -
''' same documented small per-call leak as GuiComboBoxGetSelectedText.
FUNCTION GuiTextViewGetText(tv AS GuiTextView) AS ZSTRING
    DIM realView AS TextView
    realView.handle = tv.handle
    DIM buf AS TextBuffer
    buf = TextViewGetBuffer(realView)
    DIM raw AS ANY PTR
    raw = TextBufferGetText(buf)
    DIM z AS ZSTRING
    z = raw
    GuiTextViewGetText = z
END FUNCTION

SUB GuiTextViewSetEditable(tv AS GuiTextView, editable AS INTEGER)
    DIM realView AS TextView
    realView.handle = tv.handle
    CALL TextViewSetEditable(realView, editable)
END SUB
