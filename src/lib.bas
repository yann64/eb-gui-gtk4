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
End Extern

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
