' eb-gui-gtk4's own smoke test - the same shape of program a consumer
' would write against ANY eb-gui backend: no "activate" signal handler,
' no GTK4-specific idiom at all, just the universal contract.

' Only the adapter's own interface is needed - it already carries a full
' copy of GuiApplication/GuiWindow (it #includes gui.iface.bas itself),
' so #including gui.iface.bas here too would redeclare both TYPEs.
#include "gui-gtk4.iface.bas"

DIM app AS GuiApplication
app = NewGuiApplication("io.github.yann64.eb-gui-gtk4.hellowindow")

DIM win AS GuiWindow
win = NewGuiWindow(app, "eb-gui-gtk4 Hello", 320, 200)
CALL GuiWindowShow(win)

CALL GuiApplicationRun(app)
PRINT "GuiApplicationRun returned"
