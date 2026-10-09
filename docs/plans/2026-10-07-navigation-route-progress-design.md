# Navigation: route progress tracking and rerouting

## Problem

During A→B navigation the rider went off route about 1 km after the start.
The app rerouted and then said "Continue straight onto Østerlarsvej", which was
the street they had started from. Seven minutes later they were back on the
blue route line, but the instruction had not changed and its distance had grown
from 3.1 km to 5.2 km.

Two bugs caused this:

1. **Reroutes went back to the start.** `reroute()` called
   `calculateDirections(for:from:)`, which adds a leg from the rider to the
   closest key waypoint. An A→B route has two waypoints, `[start, destination]`,
   and `min(closestIndex, count - 2)` is always 0. So every reroute went
   rider → start → destination. GPX routes had a milder form of the same bug:
   the closest waypoint can be one the rider has already passed.
2. **The instruction could get stuck.** A step advanced only when the rider came
   within 20 m of its end point. If they never passed near that point, the
   instruction stayed forever. Its distance was the straight-line distance to
   that point, so it grew as the rider rode away from it.

## Design

### Route progress

A new value type, `RouteProgress`, tracks how far along the route the rider has
come. It does not depend on `NavigationEngine` and can be unit-tested without
MapKit directions.

Each time a route is applied (initial directions or a reroute), it is rebuilt
from:

- the route line (`routeCoordinates`) and the distance along the route at each
  point;
- each step's maneuver position, found by matching the step's polyline end
  point to the route line, searching forward from the previous step.

On each location update:

1. Scan forward from the current progress up to 500 m ahead. Keep the closest
   segment within the off-route threshold (50 m for A→B, 100 m for GPX), but
   only within the first on-route stretch. Stopping at the end of that first
   stretch stops loops and out-and-back routes from jumping to the return leg.
2. On a match, project the location onto the segment. Set
   `progress = max(old, projected)` so GPS jitter cannot move it backward.
3. With no match, the rider is off route. The banner shows the closest distance
   found, and the reroute timer runs as before (3 s for A→B, 10 s for GPX).
4. The current step is the first step whose maneuver is more than 20 m ahead.
5. The distance to the next maneuver and the remaining distance are measured
   along the route from the progress point.

Voice guidance, haptics and Watch updates are unchanged. They still fire on
step changes and distance thresholds.

### Rerouting

- **A→B** (`destination_navigation`, `search_navigation`): reroute straight from
  the rider's position to the destination with MKDirections (cycling, then
  walking). The route never goes back to the start.
- **GPX and planned routes**: rejoin at the next key waypoint the rider has not
  yet reached. That is the end of the first leg that ends beyond the current
  progress, chosen by progress rather than straight-line distance. The new route
  is rider → that waypoint → the remaining waypoints. If that waypoint is the
  destination, or nothing has been recorded about the legs, route straight to
  the destination. If the shaped reroute fails, fall back to the direct route as
  before.

Unchanged: starting navigation mid-route still begins from the nearest key
waypoint, because there is no progress yet. Arrival still triggers within 30 m
of the destination and is checked first.

### Edge cases

- **Off route before any progress:** A→B routes to the destination; GPX rejoins
  at the first waypoint ahead.
- **Riding back along the route:** the forward-only scan does not match segments
  already ridden, so the rider goes off route and is routed onward.
- **GPS dropout longer than the 500 m window:** the rider shows as off route
  until a reroute replaces the route.

## Testing

A new `GiantLoggerTests` unit-test target (Swift Testing, hosted by the app)
covers `RouteProgress`:

- progress along a straight route;
- going off route and returning to the route;
- ignoring backward GPS jitter;
- an out-and-back route not jumping to the return leg;
- step advance without passing near the maneuver point;
- distances measured along the route.

Each test is checked by mutation: break the code on purpose, confirm the test
fails, then restore it. After the tests pass, the change is checked with a
simulated ride in the Simulator, deployed to the phone, and uploaded to
TestFlight.
