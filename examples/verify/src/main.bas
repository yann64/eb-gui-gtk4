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

DIM app AS GuiApplication
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

' 4. GuiApplicationQuit stops GuiApplicationRun promptly.
PRINT "calling GuiApplicationQuit..."
CALL GuiApplicationQuit(app)
CALL GuiApplicationRun(app)
PRINT "GuiApplicationRun returned - quit worked"
