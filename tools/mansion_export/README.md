# Mansion export

Makes `collection/level/mansion.glb` (the Mansion's look) from the web game, so it lines up box for box with
`collection/level/mansion_layout.json` (the colliders, ladders, lifts, spawns and short cuts).

1. Check out `PostWorkCulture/1v1` at `collection-v1` (76738cc) and get `three@0.158.0` (`npm i three@0.158.0`).
2. Copy its `index.html` to `index_patched.html` here and make two edits:
   - replace the `})();` that closes the duel script (line 14138 at 76738cc) with
     `window.__X={get M(){return M},buildMap,S,MAPS,THREE};})();`
   - in `function batchStatic`, keep prop meshes out of the merged batches so each piece of furniture stays its own node
     (`const __pm=window.__NOBATCHPROPS?new Set(M.boxes.filter(b=>b.prop&&b.mesh).map(b=>b.mesh)):null;` at the start, and
     `||(__pm&&__pm.has(o))` in the skip test of its loop)
   - the flow pass (24 Nov): `Dr` / `Wn` / `Wf` / `Gl` / `Op` carry a centre and a wanted width (doors 4.4 m, windows 4.4 m,
     glass walls become doorways), `W` grows each opening only into free wall, window sills 0.45 m up to 4.4 m, the mirror
     maze reads its panels from `window.__MIRRORS`, and `batchStatic` calls `window.__TIDY(M)` once (with `M.dbg` set) before
     merging. `tidy.js` is that pass: it drops the window panes' own meshes and moves furniture to the walls.
3. `pip install playwright` and have Chrome at `/usr/bin/google-chrome`.
4. `ROOT=<1v1 checkout> THREE=<three>/build/three.min.js OUT=raw.json python3 probe.py "$(cat tidy.js export.js)"`
   (its output also carries the new `boxes`, `windows`, `doors` and spawns for `mansion_layout.json`)
5. Decode: `python3 -c "import json,base64;d=json.load(open('raw.json'));open('mansion.glb','wb').write(base64.b64decode(d['glb']))"`

`export.js` builds the Mansion in Collection mode, moves the furniture that the web hangs under invisible collider boxes onto
plain nodes (otherwise the exporter drops it with the invisible box), drops sprites, outline edges, lights, the ball pit balls and invisible
helpers, hides glass panes (Godot draws its own so they can break), names each collider's node `box_<i>[_<prop>]` (smashable pieces are found by it) and names the
moving parts (`lift_car`, `tramp_mat`, `tramp_arrow`, `disco_ball`, `disco_floor`, `disco_beam`, `pool_water`,
`portal_swirl`) for `level/mansion_features.gd`. `boxes` in its output must match `mansion_layout.json` (1,074 boxes).

`gltf_exporter.js` is three.js r158's GLTFExporter (MIT, © three.js authors) with its imports pointed at `three-shim.js`.
