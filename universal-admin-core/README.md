# Universal Admin Core

Project Zomboid Build 42 administration tools. Requires compatible Storm on the
server and client. ATF Economy is optional.

## Administration

The panel uses Dashboard, World, Zones and Server. Search finds permitted tools
inside collapsed groups. Small windows reflow and paginate; the mouse wheel and
Previous/Next reach the remaining actions. Ctrl+A opens search when not typing.

Compact Admin provides personal pinned actions. Right-click an action to pin it.
Grouped Admin Powers support search and server-checked changes. Unavailable debug
tools are hidden; developer tools require Debug mode.

Noise actions use the server's current player position and native radius choices,
including 500 tiles. The server checks Debug Context permission and limits repeats.

Safehouse and faction lists have name/owner search and alphabetical sorting.
Faction search includes tags. Safehouse placement previews overlap and nearby
claims; the server checks placement again. Membership actions keep native
permissions. Tickets is removed from the User Panel, search and Compact Admin.

Authorized admins can expand or redraw an existing safehouse from its detail
window, with overlap feedback and recent audit history. Owner, members and
existing respawn settings stay attached to the same claim. See
[boundary editing and integration requirements](docs/SAFEHOUSE-BOUNDARY.md).

Drag a header to move a window and its bottom-right grip to resize it. Geometry
and pins persist in the native client layout file.

## Observe and Free Look

Follow, Soft Follow and Free Camera keep the admin character in place. WASD pans
Free Camera; Shift/Ctrl change speed, F focuses and Esc stops. The header button
minimizes the observer to a status bar. Teleport To and Return are separate,
server-checked actions; Teleport To works before observation starts.

The server grants a short-lived observer region sized to the viewport, at most
19 by 19 chunks. Terrain and nearby entity updates follow the accepted camera;
the character's origin stays loaded. Stop, expiry and revocation release the
region. Visibility and outdoor lighting changes apply only while rendering an
authorized observer view. Remote lamps, interiors and some roof cutaways still
have engine limits. See the [observer review](docs/OBSERVE-VISIBILITY-REVIEW.md).

Storm's object and crafting updates also honor the authorized observer region
on the current floor. Normal player relevance and interaction checks stay native.

This PR contains no safehouse respawn selector, Combat Health or Lifestyle module.
See the [operations review](ADMIN-OPERATIONS-REVIEW.md) for permissions and scope.

## Extension contract

Register actions through AdminCore/Registry.lua. Check authorization on the server.
Action metadata controls navigation, search and order without granting permission.
Server layout editing remains future work.

## Validation

Run :universal-admin-core:devCheck with the supported PZ installation. Lua fixtures
run in Lua 5.1 and the game's Kahlua interpreter; Java tests check native contracts.
