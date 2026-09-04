' Headless(-ish) verification of the eb-gui contract implemented over
' eb-gtk4 - every check is a direct function call + printed result, not
' a synthetic mouse/keyboard event (matches eb-gtk4's own
' window_lifecycle_verify.bas discipline, applied here one layer up
' through the universal API itself).

#include "gui-gtk4.iface.bas"

FUNCTION OnVetoClose(userData AS ANY PTR) AS INTEGER
    PRINT "close callback fired (veto)"
    OnVetoClose = 0
END FUNCTION

DIM triggerCount AS INTEGER

SUB OnActionTriggered(userData AS ANY PTR)
    triggerCount = triggerCount + 1
END SUB

DIM clickCount AS INTEGER

SUB OnWidgetButtonClicked(userData AS ANY PTR)
    clickCount = clickCount + 1
END SUB

DIM app AS GuiApplication

SUB OnTimeout(userData AS ANY PTR)
    PRINT "timer fired - quitting"
    CALL GuiApplicationQuit(app)
END SUB
app = NewGuiApplication("io.github.yann64.eb-gui-gtk4.verify")

' 1. Enable/disable round trip.
DIM win AS GuiWindow
win = NewGuiWindow(app, "verify", 300, 200)
PRINT "enabled by default: ", GuiWindowIsEnabled(win)
CALL GuiWindowSetEnabled(win, 0)
PRINT "enabled after SetEnabled(0): ", GuiWindowIsEnabled(win)
CALL GuiWindowSetEnabled(win, 1)
PRINT "enabled after SetEnabled(1): ", GuiWindowIsEnabled(win)

' 2. Modal + move capability query (no crash is the bar here - the
' underlying primitives are already verified at the eb-gtk4 layer).
DIM childWin AS GuiWindow
childWin = NewGuiWindow(app, "child", 200, 100)
CALL GuiWindowSetModal(childWin, win)
CALL GuiWindowClearModal(childWin)
PRINT "modal set/clear did not crash"
PRINT "can move on this backend: ", GuiWindowCanMove()
CALL GuiWindowMove(childWin, 10, 10)
PRINT "move (best-effort no-op here) did not crash"

' 3. Close callback wiring - eb-gui's own contract has no programmatic
' "request a close" call (only real user interaction, or a backend's
' own lower-level primitive, triggers one), so this only confirms
' connecting a callback doesn't crash; the actual veto/allow/no-callback
' firing behavior is already verified directly at the eb-gtk4 layer
' (window_lifecycle_verify.bas, via the lower-level WindowClose).
DIM vetoWin AS GuiWindow
vetoWin = NewGuiWindow(app, "veto", 200, 100)
CALL GuiWindowSetCloseCallback(vetoWin, @OnVetoClose, 0)
CALL GuiWindowShow(vetoWin)
PRINT "close callback connected without crashing"

' 4. StatusBar - real GtkStatusbar has no message getter, so "did not
' crash" (plus the dedicated statusbar_timer example's own live
' screenshot, in eb-gtk4 itself) is the bar here.
DIM sbWin AS GuiWindow
sbWin = NewGuiWindow(app, "statusbar", 200, 100)
DIM sb AS GuiStatusBar
sb = GuiWindowStatusBar(sbWin)
CALL GuiStatusBarShowMessage(sb, "hello")
CALL GuiStatusBarClear(sb)
PRINT "status bar show/clear did not crash"

' 6. Menu/ToolBar/Action - both should compose with the status bar
' above (all three now share sbWin's own WindowContentBox), and a
' programmatic GuiActionTrigger should genuinely reach a connected
' GuiActionConnectTriggered handler for both a menu action and a
' tool bar action.
DIM mbar AS GuiMenuBar
mbar = GuiWindowMenuBar(sbWin)
DIM fileMenu AS GuiMenu
fileMenu = GuiMenuBarAddMenu(mbar, "File")
DIM menuAction AS GuiAction
menuAction = GuiMenuAddAction(fileMenu, "Test")
CALL GuiActionConnectTriggered(menuAction, @OnActionTriggered, 0)
PRINT "before menu action trigger: ", triggerCount
CALL GuiActionTrigger(menuAction)
PRINT "after menu action trigger: ", triggerCount

CALL GuiActionSetEnabled(menuAction, 0)
CALL GuiActionSetEnabled(menuAction, 1)
PRINT "menu action enable/disable did not crash"

DIM tbar1 AS GuiToolBar
tbar1 = GuiWindowToolBar(sbWin)
DIM tbar2 AS GuiToolBar
tbar2 = GuiWindowToolBar(sbWin)
PRINT "GuiWindowToolBar returns the same handle both times: ", (tbar1.handle = tbar2.handle)

DIM toolAction AS GuiAction
toolAction = GuiToolBarAddAction(tbar1, "Go")
CALL GuiActionConnectTriggered(toolAction, @OnActionTriggered, 0)
CALL GuiActionTrigger(toolAction)
PRINT "after toolbar action trigger: ", triggerCount

' 6. Widget/Layout Round 1 - GuiBox/GuiGrid nesting, GuiEntry text
' round-trip, and GuiWindowSetContent composing correctly with
' StatusBar (already on sbWin from section 4). GuiButtonConnectClicked
' itself is only confirmed "connects without crashing" here - real
' GTK4 has no programmatic "invoke this click" primitive for a plain
' GtkButton the way BInvoker::Invoke()/g_action_activate() do for
' Haiku/GTK4 actions (GTK4 removed the old gtk_button_clicked()), and
' real interactive clicking isn't reliably driveable headlessly either
' (the same well-established limitation this whole project already
' works around for menu items via ActionActivate, which a plain button
' has no equivalent of).
DIM widgetsBox AS GuiBox
widgetsBox = NewGuiBox(1, 4)

DIM formGrid AS GuiGrid
formGrid = NewGuiGrid()
DIM nameLbl AS GuiLabel
nameLbl = NewGuiLabel("Name:")
CALL GuiGridAttach(formGrid, nameLbl.handle, 0, 0, 1, 1)
DIM nameEntry AS GuiEntry
nameEntry = NewGuiEntry("")
CALL GuiGridAttach(formGrid, nameEntry.handle, 1, 0, 1, 1)
CALL GuiBoxAddChild(widgetsBox, formGrid.handle)

CALL GuiEntrySetText(nameEntry, "hello")
PRINT "entry text round-trip: ", GuiEntryGetText(nameEntry)

DIM goBtn AS GuiButton
goBtn = NewGuiButton("Go")
CALL GuiButtonConnectClicked(goBtn, @OnWidgetButtonClicked, 0)
CALL GuiBoxAddChild(widgetsBox, goBtn.handle)

CALL GuiWindowSetContent(sbWin, widgetsBox.handle)
PRINT "GuiWindowSetContent composed with StatusBar/MenuBar/ToolBar without crashing"

' 6. Round 2: per-child constraints - expand/align/weight. GTK4's
' expand/align effect isn't introspectable headlessly (it's a layout
' allocation-time property, not a queryable widget state) - this
' confirms the calls don't crash and compose with a nested Grid.
DIM constraintsBox AS GuiBox
constraintsBox = NewGuiBox(0, 4)
DIM growBtn AS GuiButton
growBtn = NewGuiButton("Grows")
CALL GuiBoxAddChildEx(constraintsBox, growBtn.handle, 1.0, GUI_ALIGN_FILL, GUI_ALIGN_CENTER)
DIM fixedBtn AS GuiButton
fixedBtn = NewGuiButton("Fixed")
CALL GuiBoxAddChildEx(constraintsBox, fixedBtn.handle, 0.0, GUI_ALIGN_END, GUI_ALIGN_START)

DIM constraintsGrid AS GuiGrid
constraintsGrid = NewGuiGrid()
DIM gridLbl AS GuiLabel
gridLbl = NewGuiLabel("Grid cell")
CALL GuiGridAttachEx(constraintsGrid, gridLbl.handle, 0, 0, 1, 1, GUI_ALIGN_CENTER, GUI_ALIGN_CENTER)
CALL GuiGridSetColumnWeight(constraintsGrid, 0, 1.0)   ' documented no-op on this backend
CALL GuiGridSetRowWeight(constraintsGrid, 0, 1.0)      ' documented no-op on this backend
CALL GuiBoxAddChild(constraintsBox, constraintsGrid.handle)
CALL GuiBoxAddChild(widgetsBox, constraintsBox.handle)
PRINT "Round 2 constraints (GuiBoxAddChildEx/GuiGridAttachEx/GuiGridSetColumnWeight/SetRowWeight) ran without crashing"

' 7. Round 3: explicit min/max size. GuiWidgetSetMaxSize is a
' documented no-op on this backend (real GTK4 has no generic
' per-widget maximum-size API) - this confirms neither call crashes.
CALL GuiWidgetSetMinSize(fixedBtn.handle, 200, 40)
CALL GuiWidgetSetMaxSize(fixedBtn.handle, 300, 60)
PRINT "Round 3 min/max size (GuiWidgetSetMinSize/SetMaxSize) ran without crashing"

' 5. GuiTimer, and (via its own callback) GuiApplicationQuit stopping
' GuiApplicationRun - a more realistic shape than calling Quit before
' Run even starts (which this backend tolerates with a noisy assertion,
' see eb-gui-qt6's own README for why that ordering hangs there
' instead): if this program exits promptly rather than hanging, the
' timer's interval/single-shot/callback-dispatch and GuiApplicationQuit
' all genuinely work together.
DIM t AS GuiTimer
t = NewGuiTimer(win)
CALL GuiTimerSetInterval(t, 200)
CALL GuiTimerSetSingleShot(t, 1)
PRINT "timer active before start: ", GuiTimerIsActive(t)

CALL GuiTimerConnectTimeout(t, @OnTimeout, 0)
CALL GuiTimerStart(t)
PRINT "timer active after start: ", GuiTimerIsActive(t)

CALL GuiApplicationRun(app)
PRINT "GuiApplicationRun returned - timer-driven quit worked"
CALL GuiTimerDestroy(t)
