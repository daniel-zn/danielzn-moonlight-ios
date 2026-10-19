# Touch controls for the remote desktop

Artemis is a remote desktop app: the iPhone controls a PC's desktop through Apollo. This is the spec for the touch
controls of the connected screen (`Artemis/Desktop/`). It follows the conventions of the established iOS remote
desktop apps (Microsoft's Remote Desktop / Windows App, Jump Desktop, Screens): a trackpad mode by default, a direct
touch mode, two-finger tap or press-and-hold for right click, three-finger tap for the keyboard, pinch to zoom with
pan, and a movable connection bar.

## Pointer modes

**Trackpad (default).** The screen is a laptop trackpad. Artemis keeps the pointer's position itself and sends it
as an absolute position (`LiSendMousePositionEvent`), so the zoomed view can follow it exactly. A new session starts
with the pointer in the middle of the desktop.

| Gesture | Result |
|---|---|
| One finger drag | Moves the pointer, with acceleration (slow = precise, fast = far); the pointer speed setting scales it |
| Tap | Left click (the release follows 0.2 s later, so a tap then a drag can still become a drag) |
| Double tap | Double click |
| Tap, then touch again and drag | Left drag (select text, move windows) |
| Press and hold (0.45 s, haptic), then drag | Left drag |
| Press and hold, then lift without moving | Right click |
| Two-finger tap | Right click (when zoomed in, it waits 0.25 s for a second two-finger tap) |
| Two-finger drag | Scroll, both directions, high-resolution, with momentum after the fingers lift |
| Pinch | Zooms the view on the iPhone (1× to 5×); moving the fingers while pinching pans |
| Two-finger double tap | Resets the zoom |
| Three-finger tap | Shows or hides the keyboard |
| Three-finger drag | Pans the zoomed view |

**Direct.** The desktop is touched where it shows. Tap = move there and left click; drag = left drag from where the
finger went down; press and hold (haptic) = right click there; two-finger tap = right click between the fingers. Two
fingers scroll and pinch as in trackpad mode; three fingers tap and pan the same.

Switch modes from the control bar (this session) or Settings › Touch & Pointer (the default).

A gesture is decided by the most fingers it had: lifting one of two fingers doesn't turn a scroll into a pointer
move. Two fingers become a zoom when their spread changes more than their centre moves, otherwise a scroll; the
choice holds until they lift. Movement under 8 points is a tap.

## Zoom

The zoom is local (the PC's resolution doesn't change). Pinch zooms around the fingers; while zoomed the view can't
leave the desktop's edges. In trackpad mode the view follows the pointer: it scrolls when the pointer comes within 40
points of an edge. The control bar shows a reset button (`1×`) while zoomed; a two-finger double tap resets too.

## The control bar

A Liquid Glass capsule over the desktop in landscape; in portrait a row at the bottom of the screen, under the
trackpad (above the home indicator).

- Keyboard, pointer mode (trackpad / direct), controller (shows or hides the on-screen controller), shortcuts, zoom
  reset (while zoomed), disconnect (one tap ends the session, no confirming menu). There's no right-click
  button: a two-finger tap or a press and hold right-clicks. Room is left for a microphone button (mic passthrough
  is a later phase).
- In landscape it can be dragged anywhere inside the safe area (it remembers where) and folded into a small round
  button; Settings › Touch & Pointer › Show control bar decides whether a session starts unfolded. While the
  on-screen controller is up it moves to the top centre, between the controller's columns (dragging it there is
  remembered separately).

## Keyboard

The iOS keyboard, with a key row above it that sends real key events (`LiSendKeyboardEvent`):

- Esc, Tab, Ctrl, Alt, Win, Shift, the arrows, Del, Home, End, Page Up / Down, and a second page with F1–F12.
- Ctrl, Alt, Win and Shift are sticky: tap = held for the next key or click (then released), double tap = locked
  until tapped again. A typed letter with Ctrl held sends Ctrl+letter; a click with a modifier held sends e.g.
  Ctrl+click.
- Typed text: letters (Shift for capitals), digits, space, Tab and US punctuation (with Shift where a US keyboard
  needs it) as key events, the way upstream's `KeyboardSupport` translates them; other characters (accents, emoji) as
  Unicode text (`LiSendUtf8TextEvent`). Backspace and Return are keys. Keys matter on Windows' sign-in screen, UAC
  and Ctrl+Alt+Del screens (the secure desktop): they ignore Unicode text, so a password typed there must be keys.
  A password with characters that have no US key (é, £, €) can't be typed there.
- Hardware keyboards work as in upstream Moonlight (`KeyboardSupport`), with or without the on-screen keyboard.

Shortcuts menu (control bar): Copy, Paste, Undo, Select All; More Editing (Cut, Redo, Find, Save); Windows: Switch Apps (Alt+Tab), Start
(Win), Show Desktop (Win+D), File Explorer (Win+E), Task Manager (Ctrl+Shift+Esc), Close Window (Alt+F4),
Screenshot (Win+Shift+S); Type Clipboard (types the iPhone's clipboard text, as keys like typed text, so a copied
password works on the sign-in screen; the sticky modifiers don't apply). Not offered: Ctrl+Alt+Del and Win+L —
Windows reserves them (the secure attention sequence) and ignores them when they come from injected input, which is
how Apollo types.

## Layout

- **Landscape:** the desktop fills the screen (letterboxed to its aspect ratio, inside the safe area horizontally),
  with the floating control bar.
- **Portrait:** the desktop fits the top of the screen. Below it a trackpad area (always trackpad, whatever the mode;
  no click buttons: tap to click, two-finger tap or press and hold to right-click), then the control bar at the
  bottom.
- The keyboard and its key row lie on top: the desktop, the trackpad area and the control bar keep their size and
  place when it opens or closes, even where it covers them (`DesktopTests/testKeyboardOverlays`).
- Haptics: light on clicks, medium when a press and hold starts, selection ticks on modifier keys.
- **System gestures** work as in any app: one swipe from the top opens Notification or Control Centre, one swipe up
  from the bottom goes home. The session doesn't defer the screen edges (`preferredScreenEdgesDeferringSystemGestures`
  isn't overridden; the desktop's state line reads `edges none`) and doesn't hide the home indicator. The status bar
  stays hidden.

## Mapping to Moonlight's input calls

| Action | Call |
|---|---|
| Pointer position | `LiSendMousePositionEvent(x, y, streamWidth, streamHeight)` |
| Buttons | `LiSendMouseButtonEvent(BUTTON_ACTION_PRESS/RELEASE, BUTTON_LEFT/RIGHT/MIDDLE)` |
| Scroll | `LiSendHighResScrollEvent` / `LiSendHighResHScrollEvent` (120 = one notch; one notch per ~24 points at speed 1) |
| Keys | `LiSendKeyboardEvent(vk, KEY_ACTION_DOWN/UP, modifiers)` |
| Typed characters | `LiSendKeyboardEvent2(vk, …, SS_KBE_FLAG_NON_NORMALIZED)` with VK_LSHIFT around shifted ones; `LiSendUtf8TextEvent` for characters with no US key |

The calls run on one serial queue, so a click's press and release (30 ms apart) keep their order with what follows.

## Settings › Touch & Pointer

Default mode (Trackpad / Direct), Pointer speed, Natural scrolling (content follows the fingers, on by default),
Show control bar.

## Testing without a PC

`-ArtemisDemo YES` connects to a picture of a desktop instead of a stream and records the input events the gestures
produce (the desktop's accessibility value). `ArtemisUITests/DesktopTests.swift` performs each gesture and checks
the events, upright and in landscape; `testTypedPassword` types "Pa55word!" on the iOS keyboard and with Type
Clipboard and checks both are key events (Shift+P, A, 5, 5, W, O, R, D, Shift+1).

## On-screen controller

The control bar's controller button (`gamecontroller`) shows an Xbox-style controller of Liquid Glass buttons; the
PC sees an Xbox controller (`Artemis/Desktop/OnScreenGamepad.swift`, adapted from RetroPlay's pad).

- **Portrait:** it takes the trackpad's place, between the desktop and the control bar. **Landscape:** it lies over
  the desktop: a column at each side (LT LB, left stick, D-pad further in; RB RT, A B X Y, right stick further in),
  View / Xbox / Menu at the top centre, see-through glass.
- Controls: left and right sticks, D-pad (eight ways), A B X Y, LB RB, LT RT (fully pulled while held), View, Menu
  and the Xbox (Guide) button. No stick clicks (L3 / R3).
- Touch: several fingers at once (a stick, a trigger and a face button); a thumb slides between face buttons and
  holds both in the gap; a slightly missed tap goes to the nearest control (12 points); a stick measures from where
  the thumb lands (full tilt at 38 % of its width, 10 % dead zone taken out smoothly), and keeps steering off its
  edge; a D-pad touch keeps steering too. Light haptic on each new press. VoiceOver: each button presses, the D-pad
  and sticks have direction actions.
- Touches on the controller don't move the pointer; in landscape, touches between its controls go to the desktop as
  usual. The keyboard lies over it (nothing moves).
- Each session starts with it hidden (not remembered: a remote desktop session usually wants the trackpad first);
  it stays up across rotation.
- To the PC: `connectVirtualGamepad` / `sendVirtualGamepadButtons…` / `disconnectVirtualGamepad` in
  `ControllerSupport`. With Multiple controllers on, it takes the first player number (0–3) no connected controller
  has, controllers connecting later skip it, and the active-gamepad mask includes it (Apollo takes up to 16; with
  four controllers connected it's number 4); with it off it's player 1 like every controller, and its state and the
  connected controllers' are merged (buttons together, the larger trigger and stick), so neither releases what the
  other holds. Arrival (`LiSendControllerArrivalEvent`, `LI_CTYPE_XBOX`, its buttons) goes with its first
  state, sent as soon as it shows (`LiSendMultiControllerEvent`, at rest). Hiding it, disconnecting or leaving the
  session sends it at rest, then without its bit in the mask, so the PC removes it. Fingers lifting with the app
  going away release everything.
- Settings › Controllers › On-Screen Controller: Size (Small / Medium / Large: 80 / 90 / 100 % of the space it
  gets, Medium by default) and Opacity over the desktop (landscape, 30–100 %, 85 % by default).
- Tests: `OnScreenGamepadTests` (the demo desktop records `gamepad connect`, `gamepad <buttons> lt rt ls x y rs x y`,
  `gamepad disconnect`): A, RT, Guide, Menu, D-pad, both sticks, A + LT + a stick at once, shown and hidden in
  portrait and landscape, large text.

## Game controllers

A controller connected to the iPhone (Xbox, PlayStation, MFi) goes to the PC as a gamepad (upstream's
`ControllerSupport`; upstream's on-screen controls are never shown, Artemis has its own above). Start, Select, LB
and RB together disconnect.

**As the mouse.** Hold Start (Menu) for 0.75 s to switch the controller to the mouse; a notice says "Controller
mouse on". Hold it again to switch back. While it's the mouse, nothing goes to the PC as a gamepad.

| Control | Result |
|---|---|
| Left stick | Moves the pointer (squared response past a 15 % dead zone; 1500 px/s at full tilt × the pointer speed) |
| Right stick | Scrolls, both directions (up to 12 notches a second) |
| A / B / X | Left / right / middle button (held while held) |
| LB / RB | Back / forward |
| D-pad | One scroll step |
| Y | Shows or hides the keyboard |

Settings › Controllers › Mouse control with a controller (on by default) allows the long press. The mapping is
`Artemis/Desktop/GamepadMouse.swift`; `ControllerSupport` hands it each controller's state before sending it.

