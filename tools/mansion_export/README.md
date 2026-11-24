# Mansion export

Makes `collection/level/mansion.glb` (the Mansion's look) from the web game, so it lines up box for box with
`collection/level/mansion_layout.json` (the colliders, ladders, lifts, spawns and short cuts).

1. Check out `PostWorkCulture/1v1` at `collection-v1` (76738cc) and get `three@0.158.0` (`npm i three@0.158.0`).
2. Copy its `index.html` to `index_patched.html` here and replace the `})();` that closes the duel script
   (line 14138 at 76738cc) with `window.__X={get M(){return M},buildMap,S,MAPS,THREE};})();`
3. `pip install playwright` and have Chrome at `/usr/bin/google-chrome`.
4. `ROOT=<1v1 checkout> THREE=<three>/build/three.min.js OUT=raw.json python3 probe.py "$(cat export.js)"`
5. Decode: `python3 -c "import json,base64;d=json.load(open('raw.json'));open('mansion.glb','wb').write(base64.b64decode(d['glb']))"`

`export.js` builds the Mansion in Collection mode, drops sprites, outline edges, lights, the ball pit balls and invisible
helpers, hides glass panes (Godot draws its own so they can break), names each collider's mesh `box_<i>` and names the
moving parts (`lift_car`, `tramp_mat`, `tramp_arrow`, `disco_ball`, `disco_floor`, `disco_beam`, `pool_water`,
`portal_swirl`) for `level/mansion_features.gd`. `boxes` in its output must match `mansion_layout.json` (1,074 boxes).

`gltf_exporter.js` is three.js r158's GLTFExporter (MIT, © three.js authors) with its imports pointed at `three-shim.js`.
