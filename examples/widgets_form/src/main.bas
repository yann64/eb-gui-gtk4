' Live example: a GuiBox containing a GuiLabel + GuiEntry + GuiButton -
' clicking the button reads the entry's text and updates the label,
' via eb-gui's universal Widget/Layout Round 1 contract.

#include "gui-gtk4.iface.bas"

CONST GUI_ORIENTATION_VERTICAL = 1

DIM lbl AS GuiLabel

SUB OnClicked(userData AS ANY PTR)
    DIM e AS GuiEntry
    e.handle = userData
    CALL GuiLabelSetText(lbl, GuiEntryGetText(e))
END SUB

DIM app AS GuiApplication
app = NewGuiApplication("io.github.yann64.eb-gui-gtk4.widgetsform")

DIM win AS GuiWindow
win = NewGuiWindow(app, "eb-gui-gtk4 Widgets Form", 320, 200)

DIM formBox AS GuiBox
formBox = NewGuiBox(GUI_ORIENTATION_VERTICAL, 8)

lbl = NewGuiLabel("Type something, then click Go")
CALL GuiBoxAddChild(formBox, lbl.handle)

DIM entryField AS GuiEntry
entryField = NewGuiEntry("")
CALL GuiBoxAddChild(formBox, entryField.handle)

DIM btn AS GuiButton
btn = NewGuiButton("Go")
CALL GuiButtonConnectClicked(btn, @OnClicked, entryField.handle)
CALL GuiBoxAddChild(formBox, btn.handle)

CALL GuiWindowSetContent(win, formBox.handle)
CALL GuiWindowShow(win)

CALL GuiApplicationRun(app)
PRINT "GuiApplicationRun returned"
