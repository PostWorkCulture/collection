/* Collection (Godot) export: tidy the web Mansion so it flows (Pete, 24 Nov 2026).
   Runs inside the web build just before its static batching (window.__TIDY hook in index_tidy.html):
   - drops every glass pane's own mesh (Godot draws the glass itself, so it can break; the batched copies made the house
     look milky from outside), keeping anything hung under a pane
   - pushes free-standing furniture back against the nearest wall it fits on, clear of doors, windows and open gaps,
     away from the toys (tubs, ball pit, pole, lifts, trampolines, pool, dance floor, portals) and the stairs
   Leaves a report in window.__TIDY_REPORT. */
window.__TIDY = function (M) {
  const T = window.__X.THREE, R = M.dbg.R, D = M.dbg.DOORS, WN = M.dbg.WINS;
  const rep = { underWindow: [], turned: 0, removed: [], glassMeshes: 0, clusters: 0, moved: 0, stayed: [], against: 0, big: 0, special: 0 };
  M.group.updateMatrixWorld(true);
  /* ---- glass */
  for (const b of M.boxes) {
    if (!b.mesh) continue;
    if (b.prop === 'glass' || b.color === '#bfe6ff') {
      const m = b.mesh;
      if (!m.isMesh) continue;
      if (b.prop === 'glass' && m.children.length) continue; // mirrors and cases: the export keeps their pieces
      for (const c of m.children.slice()) M.group.attach(c);
      if (m.parent) m.parent.remove(m);
      rep.glassMeshes++;
    }
  }
  /* ---- furniture */
  const UF = 5.8;
  const special = [
    [-16, 4, 1, 3.6], [30, 23, 1, 3.6], [-36, 5, 1, 4.2], [-32, 0, 2, 2.6], [-22.35, 25.5, 2, 2.3], [22.35, -7.5, 2, 2.3],
    [32, 0, 0, 2.8], [27.5, -5.5, 0, 2.2], [36.5, 5.5, 0, 2.2], [-16, 17, 0, 6.5], [-39.75, 18, 2, 2.4], [39.75, -18, 2, 2.4]];
  const zones = [ // x0, x1, z0, z1, floor (0, 1, 2 = both)
    [10.4, 21.6, -5.6, 5.6, 0], [-2.8, 2.8, -2, 7.4, 2], [-40, -36.2, -17.4, -10.4, 2], [36.2, 40, 10.4, 17.4, 2]];
  const inSpecial = (x0, x1, z0, z1, fl) => {
    for (const [x, z, f, r] of special) {
      if (f !== 2 && f !== fl) continue;
      const cx = Math.max(x0, Math.min(x, x1)), cz = Math.max(z0, Math.min(z, z1));
      if (Math.hypot(cx - x, cz - z) < r) return true;
    }
    for (const [a0, a1, b0, b1, f] of zones) {
      if (f !== 2 && f !== fl) continue;
      if (x1 > a0 && x0 < a1 && z1 > b0 && z0 < b1) return true;
    }
    return false;
  };
  // openings to keep clear: [x0, x1, z0, z1, floorY]
  const zonesFor = (dd, wd, pad, noWin) => {
    const out = [];
    for (const d of D) {
      const h = d.w / 2 + pad;
      if (d.ax) out.push([d.x - h, d.x + h, d.z - dd, d.z + dd, d.y]);
      else out.push([d.x - dd, d.x + dd, d.z - h, d.z + h, d.y]);
    }
    for (const w of (noWin ? [] : WN.filter(w => w.pane))) {   // fixed side windows don't open
      const y = w.s0 > 5 ? UF : 0;
      if (w.ax) out.push([w.a - pad, w.b + pad, w.at - wd, w.at + wd, y]);
      else out.push([w.at - wd, w.at + wd, w.a - pad, w.b + pad, y]);
    }
    return out;
  };
  const strict = zonesFor(2.0, 1.6, 0.4), loose = zonesFor(1.4, 0.9, 0.1), doorsOnly = zonesFor(1.4, 0, 0.1, true);
  let clear = strict;
  const blocked = (x0, x1, z0, z1, fy) => clear.some(c => Math.abs(c[4] - fy) < 0.5 && x1 > c[0] && x0 < c[1] && z1 > c[2] && z0 < c[3]);

  // every mesh's world box, once
  const meshes = [];
  M.group.traverse(o => {
    if (!o.isMesh || !o.geometry || o.isInstancedMesh) return;
    if (!o.geometry.boundingBox) o.geometry.computeBoundingBox();
    const bb = o.geometry.boundingBox.clone().applyMatrix4(o.matrixWorld);
    meshes.push({ o, bb });
  });

  const rooms = Object.entries(R).filter(([n]) => n !== 'terrace');
  for (const [name, q] of rooms) {
    const fy = q.y, fl = fy > 1 ? 1 : 0;
    const ix0 = q.x0 + 0.2, ix1 = q.x1 - 0.2, iz0 = q.z0 + 0.2, iz1 = q.z1 - 0.2;
    // boxes standing in this room
    const inRoom = M.boxes.filter(b => {
      const cx = (b.x0 + b.x1) / 2, cz = (b.z0 + b.z1) / 2;
      return cx > ix0 && cx < ix1 && cz > iz0 && cz < iz1 && b.y0 >= fy - 0.05 && b.y1 <= fy + 3.4 && b.y0 < fy + 2.6;
    }).filter(b => Math.max(b.x1 - b.x0, b.z1 - b.z0) < 11 && !(Math.min(b.x1 - b.x0, b.z1 - b.z0) <= 0.45 && b.y1 - b.y0 > 2.9) && !(b.see));
    if (!inRoom.length) continue;
    // clusters: boxes that touch
    const par = inRoom.map((_, i) => i);
    const find = i => par[i] === i ? i : (par[i] = find(par[i]));
    for (let i = 0; i < inRoom.length; i++) for (let j = i + 1; j < inRoom.length; j++) {
      const a = inRoom[i], b = inRoom[j], g = 0.12;
      if (a.x1 + g > b.x0 && b.x1 + g > a.x0 && a.z1 + g > b.z0 && b.z1 + g > a.z0) par[find(i)] = find(j);
    }
    const groups = new Map();
    inRoom.forEach((b, i) => { const k = find(i); if (!groups.has(k)) groups.set(k, []); groups.get(k).push(b); });
    const placed = []; // footprints already against walls (after moves) to avoid
    const fp = list => {
      let x0 = 1e9, x1 = -1e9, z0 = 1e9, z1 = -1e9, top = -1e9, low = 1e9;
      for (const b of list) { x0 = Math.min(x0, b.x0); x1 = Math.max(x1, b.x1); z0 = Math.min(z0, b.z0); z1 = Math.max(z1, b.z1); top = Math.max(top, b.y1); low = Math.min(low, b.y0); }
      return { x0, x1, z0, z1, top, low };
    };
    const clusters = [...groups.values()].map(list => ({ list, f: fp(list) })).filter(c => c.f.low < fy + 0.35);
    for (const c of clusters) {
      const f = c.f;
      c.blocks = blocked(f.x0, f.x1, f.z0, f.z1, fy) && !inSpecial(f.x0, f.x1, f.z0, f.z1, fl);
      const dWall = Math.min(f.x0 - ix0, ix1 - f.x1, f.z0 - iz0, iz1 - f.z1);
      if (dWall < 0.7 && !c.blocks) { rep.against++; placed.push(f); }
    }
    const others = (c, x0, x1, z0, z1) => inRoom.some(b => !c.list.includes(b) && b.y0 < fy + 2.2 && x1 + 0.05 > b.x0 && b.x1 + 0.05 > x0 && z1 + 0.05 > b.z0 && b.z1 + 0.05 > z0)
      || placed.some(p => x1 + 0.05 > p.x0 && p.x1 + 0.05 > x0 && z1 + 0.05 > p.z0 && p.z1 + 0.05 > z0);
    for (const c of clusters) {
      const f = c.f;
      const w = f.x1 - f.x0, d = f.z1 - f.z0;
      const dWall = Math.min(f.x0 - ix0, ix1 - f.x1, f.z0 - iz0, iz1 - f.z1);
      if (dWall < 0.7 && !c.blocks) continue;
      rep.clusters++;
      if (w * d > 14 && !c.blocks) { rep.big++; rep.stayed.push(name + ': big ' + w.toFixed(1) + 'x' + d.toFixed(1)); continue; }
      if (!c.blocks && inSpecial(f.x0, f.x1, f.z0, f.z1, fl)) { rep.special++; continue; }
      // try each wall, nearest first, sliding along it; as it stands, then turned a quarter; strict clearances, then looser
      const cx0 = (f.x0 + f.x1) / 2, cz0 = (f.z0 + f.z1) / 2;
      let best = null;
      for (const zs of (fl ? [strict, loose, doorsOnly] : [strict, loose])) {   // ground-floor windows are kept clear
        clear = zs;
        for (const rot of [0, 1]) {
          const hw = (rot ? d : w) / 2, hd = (rot ? w : d) / 2;
          const g = { x0: cx0 - hw, x1: cx0 + hw, z0: cz0 - hd, z1: cz0 + hd };
          const walls = [
            [ix0 + 0.06 - g.x0, 0, 'z', g.x0 - ix0], [ix1 - 0.06 - g.x1, 0, 'z', ix1 - g.x1],
            [0, iz0 + 0.06 - g.z0, 'x', g.z0 - iz0], [0, iz1 - 0.06 - g.z1, 'x', iz1 - g.z1]].sort((p, q) => p[3] - q[3]);
          for (const [dx, dz, ax] of walls) {
            for (let k = 0; k <= 30 && !best; k++) {
              const sl = (k % 2 ? 1 : -1) * Math.ceil(k / 2) * 0.5;
              const mx = dx + (ax === 'x' ? sl : 0), mz = dz + (ax === 'z' ? sl : 0);
              const x0 = g.x0 + mx, x1 = g.x1 + mx, z0 = g.z0 + mz, z1 = g.z1 + mz;
              if (x0 < ix0 || x1 > ix1 || z0 < iz0 || z1 > iz1) continue;
              if (blocked(x0 - 0.2, x1 + 0.2, z0 - 0.2, z1 + 0.2, fy)) continue;
              if (inSpecial(x0, x1, z0, z1, fl)) continue;
              if (others(c, x0, x1, z0, z1)) continue;
              best = [mx, mz, rot];
              if (zs === doorsOnly) rep.underWindow.push(name);
            }
            if (best) break;
          }
          if (best) break;
        }
        if (best) break;
      }
      clear = strict;
      const pieces = () => {
      const set = new Set();
      for (const b of c.list) if (b.mesh && b.mesh.parent) set.add(b.mesh);
      for (const m of meshes) {
        const bb = m.bb, cx = (bb.min.x + bb.max.x) / 2, cz = (bb.min.z + bb.max.z) / 2, cy = (bb.min.y + bb.max.y) / 2;
        if (cx < f.x0 - 0.15 || cx > f.x1 + 0.15 || cz < f.z0 - 0.15 || cz > f.z1 + 0.15) continue;
        if (cy < fy - 0.05 || cy > f.top + 1.0) continue;
        if (bb.max.x - bb.min.x > w + 0.4 || bb.max.z - bb.min.z > d + 0.4) continue; // rugs, floors
        set.add(m.o);
      }
      return [...set].filter(o => o.parent).filter(o => { for (let p = o.parent; p && p !== M.group; p = p.parent) if (set.has(p)) return false; return true; });
      };
      const where = name + ' ' + w.toFixed(1) + 'x' + d.toFixed(1) + ' at ' + ((f.x0 + f.x1) / 2).toFixed(1) + ',' + ((f.z0 + f.z1) / 2).toFixed(1);
      clear = doorsOnly;
      const blocksDoor = blocked(f.x0, f.x1, f.z0, f.z1, fy);
      clear = strict;
      if (!best && c.blocks && (blocksDoor || fl === 0)) {   // in a doorway or under a ground-floor window with nowhere else to go: it goes
        for (const o of pieces()) o.parent.remove(o);
        for (const b of c.list) { const i = M.boxes.indexOf(b); if (i >= 0) M.boxes.splice(i, 1); }
        rep.removed.push(where); continue;
      }
      if (!best) { rep.stayed.push(where); continue; }
      const [mx, mz, rot] = best;
      const roots = pieces();
      // world move: turn a quarter about the footprint's centre (if asked), then shift
      const mv = new T.Matrix4().makeTranslation(cx0 + mx, 0, cz0 + mz)
        .multiply(new T.Matrix4().makeRotationY(rot ? Math.PI / 2 : 0))
        .multiply(new T.Matrix4().makeTranslation(-cx0, 0, -cz0));
      for (const m of meshes) { for (let p = m.o; p && p !== M.group; p = p.parent) if (roots.includes(p)) { m.bb.applyMatrix4(mv); break; } }
      for (const o of roots) {
        o.updateMatrixWorld(true);
        const wm = mv.clone().multiply(o.matrixWorld);
        const local = new T.Matrix4().copy(o.parent.matrixWorld).invert().multiply(wm);
        local.decompose(o.position, o.quaternion, o.scale);
        o.updateMatrixWorld(true);
      }
      for (const b of c.list) {
        const bx = (b.x0 + b.x1) / 2 - cx0, bz = (b.z0 + b.z1) / 2 - cz0, hx = (b.x1 - b.x0) / 2, hz = (b.z1 - b.z0) / 2;
        const nx = rot ? bz : bx, nz = rot ? -bx : bz, nhx = rot ? hz : hx, nhz = rot ? hx : hz;
        b.x0 = cx0 + mx + nx - nhx; b.x1 = cx0 + mx + nx + nhx; b.z0 = cz0 + mz + nz - nhz; b.z1 = cz0 + mz + nz + nhz;
      }
      const hw2 = (rot ? d : w) / 2, hd2 = (rot ? w : d) / 2;
      placed.push({ x0: cx0 + mx - hw2, x1: cx0 + mx + hw2, z0: cz0 + mz - hd2, z1: cz0 + mz + hd2 });
      if (rot) rep.turned++;
      rep.moved++;
    }
  }
  window.__TIDY_REPORT = rep;
};
