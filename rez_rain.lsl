// Random rez around a center with random Z rotation
// — Christian's rezzer —
// Put the object named in REZ_NAME (copy-perm) into this prim's inventory.

string  REZ_NAME       = "Plane_rain";                 // object to rez
vector  CENTER_POS     = <128.0, 128.0, 3500.0>;       // starting center
float   RADIUS         = 10.0;                           // base radius (meters)
float   RADIUS_OFFSET  = 0.0;                           // optional extra radius
integer CLAMP_TO_REGION = TRUE;                         // keep inside [0..256] on X/Y
integer nb_rain = 10;

// --- wander settings (move rezzer before rezzing) ---
float   WANDER_RADIUS_XY = 0.0;                        // randomize around CENTER_POS in XY
float   WANDER_Z_DELTA   = 0.0;                         // random Z offset in [-delta, +delta]

// link message number to trigger "move then rez"
integer LINK_REZ_CMD = 9100;

// ============== helpers ==============
float clamp(float v, float lo, float hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

// Uniform random point in a circle (not donut): r = R*sqrt(U), theta = 2?U
vector randomOffsetInCircle(float effectiveRadius) {
    float theta = llFrand(TWO_PI);
    float r = effectiveRadius * llSqrt(llFrand(1.0));
    return <llCos(theta)*r, llSin(theta)*r, 0.0>;
}

vector clampToRegionXY(vector p) {
    float margin = 0.2; // small border margin
    p.x = clamp(p.x, 0.0 + margin, 256.0 - margin);
    p.y = clamp(p.y, 0.0 + margin, 256.0 - margin);
    return p;
}

// === your rotation builder (left unchanged as requested) ===
rotation buildSpawnRotation()
{
    // 1) Base Y +90° (your original lines kept)
    rotation rY90 = llEuler2Rot(<90.0 * DEG_TO_RAD, 0, 0.0>);

    // 2) Random tilt on X and Y: each in [-20°, +20°]
    float tiltX = (llFrand(40.0) - 20.0) * DEG_TO_RAD;
    //float tiltY = (llFrand(0.0) - 20.0) * DEG_TO_RAD;
    rotation rTilt = llEuler2Rot(<tiltX, 0, 0.0>);

    // 3) Random yaw on Z: [0°, 360°)
    float yawDeg = llFrand(360.0);
    rotation rZ = llEuler2Rot(<0.0, 0.0, yawDeg * DEG_TO_RAD>);

    // Apply order kept per your last version
    //return rZ * rTilt * rY90;
    return rY90 * rZ * rTilt;
}

// ============== core (UNCHANGED doRez) ==============
integer doRez() {
    if (llGetInventoryType(REZ_NAME) != INVENTORY_OBJECT) {
        llOwnerSay("Rez failed: object \"" + REZ_NAME + "\" not found in inventory.");
        return FALSE;
    }

    float effectiveRadius = RADIUS + RADIUS_OFFSET;

    integer i = 0;
    while (i < nb_rain ) {
        vector pos = CENTER_POS + randomOffsetInCircle(effectiveRadius);
        if (CLAMP_TO_REGION) pos = clampToRegionXY(pos);

        rotation rot = buildSpawnRotation();
        vector vel = ZERO_VECTOR;

        // start_param = i+1 so each object can know its index if needed
        llRezAtRoot(REZ_NAME, pos, vel, rot, i + 1);

        // tiny stagger to avoid throttle; adjust if you hit rate limits
        llSleep(0.1);
        i++;
    }
    return TRUE;
}

// ============== move-then-rez ==============
moveThenRez()
{
    // compute a new randomized center around the current CENTER_POS
    vector offXY = randomOffsetInCircle(WANDER_RADIUS_XY);
    float zOff = 0.0;
    if (WANDER_Z_DELTA > 0.0) {
        zOff = (llFrand(2.0 * WANDER_Z_DELTA) - WANDER_Z_DELTA);
    }
    vector target = CENTER_POS + <offXY.x, offXY.y, zOff>;
    if (CLAMP_TO_REGION) target = clampToRegionXY(target);

    // move the rezzer first
    llSetRegionPos(target);

    // IMPORTANT: keep your doRez() unchanged by simply updating CENTER_POS
    CENTER_POS = llGetPos(); // doRez() will use this as its center

    // now rez the batch
    doRez();
}

// ============== events ==============
default
{
    state_entry() {
        // nothing else needed
    }

    // Trigger from another script in the linkset:
    // llMessageLinked(LINK_SET, 9100, "", NULL_KEY);
    link_message(integer sender, integer num, string msg, key id) {
        if (num == LINK_REZ_CMD) {
            moveThenRez();
        }
    }

    on_rez(integer start_param) { llResetScript(); }
}
