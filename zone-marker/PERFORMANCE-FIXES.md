# Map cache and editor synchronization

The overlay caches enabled zone records and label widths until the zone revision or
filter selection changes. Each render calculates current viewport bounds, including all
four corners for rotated maps, and skips zones outside them before drawing. Labels that
overlap the viewport are retained. Pan, zoom and resize use fresh screen coordinates.

The editor invalidates lists on `ZoneMarkerCache.version`, so same-count replacements,
renamed categories and current selections refresh correctly. The options wrapper also
refreshes category labels when AVCS installed the shared map-options hook first.

Run `lua zone-marker/tests/CacheAndRenderer.lua` from the repository root. Five regression
checks pass in Lua 5.1 and the installed B42.20.4 Kahlua interpreter. Java compilation and
jar assembly pass; this module currently has no Java test sources. In-game map interaction
and large-zone performance measurements remain pending.
