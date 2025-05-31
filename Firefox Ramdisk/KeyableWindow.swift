import Cocoa

// Your window is borderless (you created it with .borderless styleMask),
// and by default borderless windows cannot become key or main windows.
// Without being key, the window can’t get keyboard events or certain UI focus.
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}
