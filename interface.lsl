// Receiver: Fade In / Out controlled by JSON over llRegionSay or link messages
// Listens on the channel provided via rez parameter (llRezObject param)
// Expects: {"COMMAND":"start"|"stop", optional "NAME" matching this object's name}

// ---- Config ----
integer FILTER_BY_NAME = TRUE;    // require NAME to match llGetObjectName()
integer EXCLUDE_ROOT   = TRUE;    // TRUE = skip link 1 (root) when fading
integer ENABLE_DEBUG   = TRUE;    // when TRUE log state changes with llOwnerSay

// Fade tuning
float STEP_TIME     = 0.02;
float FADE_IN_TIME  = 2.2;
float FADE_OUT_TIME = 2.8;

float MIN_VIS       = 0.00;
float MAX_VIS       = 0.985;
float SMOOTH_FACTOR = 0.25;
float WRITE_EPS     = 0.0005;

// PBR alpha mode
integer MODE_BLEND  = PRIM_GLTF_ALPHA_MODE_BLEND;
integer MODE_OPAQUE = PRIM_GLTF_ALPHA_MODE_OPAQUE;

// Texture configuration
string TEXTURE_CONFIG = "textures.json";
string TEXTURE_BLANK  = "b7ebe3f4-6a5e-9128-7540-403549c69bc6";

// Notecard helpers
string NOTE_EOF        = EOF;
string NOTE_NOT_FOUND  = "NOT_FOUND";
string NOTE_NOT_READY  = "NOT_READY";
string NOTE_NAK        = NAK;

// Configuration stride: [Link, Face, Mode, TextureId, Alpha, Glow, Speed, Rotation]
integer CFG_LINK     = 0;
integer CFG_FACE     = 1;
integer CFG_MODE     = 2;
integer CFG_TEXTURE  = 3;
integer CFG_ALPHA    = 4;
integer CFG_GLOW     = 5;
integer CFG_SPEED    = 6;
integer CFG_ROTATION = 7;
integer CFG_STRIDE   = 8;

// ---- State ----
integer gListen = 0;
integer gDir = 0;      // 1=in, -1=out, 0=idle
float   gProg = 0.0;
float   gATarget = 0.0;
float   gALive   = 0.0;
string  gMyName;
integer gChannel = 0;
integer gDieAfterFade = FALSE;

// Texture configuration state
list    gTextureTargets = [];
integer gTexturesReady = FALSE;
integer gTextureLine = 0;
integer gTextureLoading = FALSE;
key     gTextureRequest = NULL_KEY;

// Quintic easing 0..1 -> 0..1
float ease5(float t) { return t*t*t * (t*(6.0*t - 15.0) + 10.0); }

// --- Helpers ---
integer has_texture_config()
{
    return gTexturesReady && llGetListLength(gTextureTargets) >= CFG_STRIDE;
}

integer parse_texture_mode(string modeStr)
{
    if (modeStr == JSON_INVALID || modeStr == "")
    {
        return MODE_OPAQUE;
    }

    string normalized = llToUpper(llStringTrim(modeStr, STRING_TRIM));
    if (normalized == "BLEND") return MODE_BLEND;
    if (normalized == "MASK") return PRIM_GLTF_ALPHA_MODE_MASK;
    if (normalized == "OPAQUE") return MODE_OPAQUE;
    return MODE_OPAQUE;
}

integer find_texture_entry(integer link, integer face)
{
    integer len = llGetListLength(gTextureTargets);
    integer i;
    for (i = 0; i < len; i += CFG_STRIDE)
    {
        if (llList2Integer(gTextureTargets, i + CFG_LINK) == link &&
            llList2Integer(gTextureTargets, i + CFG_FACE) == face)
        {
            return i;
        }
    }
    return -1;
}

integer apply_config_modes()
{
    if (!has_texture_config())
    {
        return FALSE;
    }

    integer len = llGetListLength(gTextureTargets);
    integer i;
    for (i = 0; i < len; i += CFG_STRIDE)
    {
        integer link = llList2Integer(gTextureTargets, i + CFG_LINK);
        integer face = llList2Integer(gTextureTargets, i + CFG_FACE);
        integer mode = llList2Integer(gTextureTargets, i + CFG_MODE);

        llSetLinkGLTFOverrides(link, face, [
            OVERRIDE_GLTF_BASE_ALPHA_MODE, mode
        ]);
    }

    return TRUE;
}

integer apply_blank_textures()
{
    if (!has_texture_config())
    {
        return FALSE;
    }

    integer len = llGetListLength(gTextureTargets);
    integer i;
    for (i = 0; i < len; i += CFG_STRIDE)
    {
        integer link = llList2Integer(gTextureTargets, i + CFG_LINK);
        integer face = llList2Integer(gTextureTargets, i + CFG_FACE);

        llSetLinkGLTFOverrides(link, face, [
            OVERRIDE_GLTF_BASE_COLOR_TEXTURE, TEXTURE_BLANK,
            OVERRIDE_GLTF_BASE_ALPHA_MODE, MODE_BLEND
        ]);

        llSetLinkPrimitiveParamsFast(link, [
            PRIM_GLOW, face, 0.0
        ]);
    }

    return TRUE;
}

integer apply_final_textures()
{
    if (!has_texture_config())
    {
        return FALSE;
    }

    integer len = llGetListLength(gTextureTargets);
    integer i;
    for (i = 0; i < len; i += CFG_STRIDE)
    {
        integer link = llList2Integer(gTextureTargets, i + CFG_LINK);
        integer face = llList2Integer(gTextureTargets, i + CFG_FACE);
        integer mode = llList2Integer(gTextureTargets, i + CFG_MODE);
        string  tex  = llList2String(gTextureTargets, i + CFG_TEXTURE);
        float   glow = llList2Float(gTextureTargets, i + CFG_GLOW);

        llSetLinkGLTFOverrides(link, face, [
            OVERRIDE_GLTF_BASE_COLOR_TEXTURE, tex,
            OVERRIDE_GLTF_BASE_ALPHA_MODE, mode
        ]);

        llSetLinkPrimitiveParamsFast(link, [
            PRIM_GLOW, face, glow
        ]);
    }

    return TRUE;
}

integer parse_texture_entry(string jsonLine)
{
    if (jsonLine == "")
    {
        return FALSE;
    }

    string textureId = llJsonGetValue(jsonLine, ["Texture"]);
    if (textureId == JSON_INVALID || textureId == "")
    {
        Debug("Skipping texture entry missing Texture: " + jsonLine);
        return FALSE;
    }

    integer link = (integer)llJsonGetValue(jsonLine, ["Link"]);
    integer face = (integer)llJsonGetValue(jsonLine, ["Face"]);

    if (link <= 0)
    {
        Debug("Skipping texture entry with invalid link: " + jsonLine);
        return FALSE;
    }

    string modeStr = llJsonGetValue(jsonLine, ["Mode"]);
    integer mode = parse_texture_mode(modeStr);

    float alpha = 1.0;
    string alphaStr = llJsonGetValue(jsonLine, ["Alpha"]);
    if (alphaStr != JSON_INVALID && alphaStr != "")
    {
        alpha = (float)alphaStr;
        if (alpha < 0.0) alpha = 0.0;
        if (alpha > 1.0) alpha = 1.0;
    }

    float glow = 0.0;
    string glowStr = llJsonGetValue(jsonLine, ["Glow"]);
    if (glowStr != JSON_INVALID && glowStr != "")
    {
        glow = (float)glowStr;
        if (glow < 0.0) glow = 0.0;
    }

    float speed = 0.0;
    string speedStr = llJsonGetValue(jsonLine, ["Speed"]);
    if (speedStr != JSON_INVALID && speedStr != "")
    {
        speed = (float)speedStr;
    }

    float rotation = 0.0;
    string rotStr = llJsonGetValue(jsonLine, ["Rotation"]);
    if (rotStr != JSON_INVALID && rotStr != "")
    {
        rotation = (float)rotStr;
    }

    gTextureTargets += [link, face, mode, textureId, alpha, glow, speed, rotation];
    return TRUE;
}

integer request_next_texture_line()
{
    gTextureRequest = llGetNotecardLine(TEXTURE_CONFIG, gTextureLine);
    if (gTextureRequest == NULL_KEY)
    {
        Debug("Failed to request line " + (string)gTextureLine + " from " + TEXTURE_CONFIG);
        gTextureLoading = FALSE;
        return FALSE;
    }

    gTextureLoading = TRUE;
    return TRUE;
}

integer start_texture_config_load()
{
    gTextureTargets = [];
    gTexturesReady = FALSE;
    gTextureLine = 0;
    gTextureLoading = FALSE;
    gTextureRequest = NULL_KEY;

    if (llGetInventoryType(TEXTURE_CONFIG) != INVENTORY_NOTECARD)
    {
        Debug("Texture configuration notecard '" + TEXTURE_CONFIG + "' not found.");
        return FALSE;
    }

    return request_next_texture_line();
}

integer on_texture_config_ready()
{
    if (!has_texture_config())
    {
        Debug("Texture configuration loaded but contains no entries.");
        return FALSE;
    }

    if (gDir != 0 || gALive <= (MIN_VIS + WRITE_EPS))
    {
        apply_blank_textures();
    }
    else
    {
        apply_final_textures();
        apply_config_modes();
    }

    Debug("Loaded " + (string)(llGetListLength(gTextureTargets) / CFG_STRIDE) + " texture overrides from '" + TEXTURE_CONFIG + "'.");
    return TRUE;
}

integer set_all_mode(integer mode)
{
    integer n = llGetNumberOfPrims();
    integer startLink; if (EXCLUDE_ROOT) startLink = 2; else startLink = 1;

    integer L;
    for (L = startLink; L <= n; ++L)
    {
        integer faces = llGetLinkNumberOfSides(L);
        integer f;
        for (f = 0; f < faces; ++f)
        {
            llSetLinkGLTFOverrides(L, f, [
                OVERRIDE_GLTF_BASE_ALPHA_MODE, mode
            ]);
        }
    }
    return TRUE;
}

integer set_all_alpha(float a)
{
    integer n = llGetNumberOfPrims();
    integer startLink; if (EXCLUDE_ROOT) startLink = 2; else startLink = 1;

    integer L;
    for (L = startLink; L <= n; ++L)
    {
        integer faces = llGetLinkNumberOfSides(L);
        integer f;
        for (f = 0; f < faces; ++f)
        {
            float faceAlpha = a;
            integer idx = find_texture_entry(L, f);
            if (idx >= 0)
            {
                float entryAlpha = llList2Float(gTextureTargets, idx + CFG_ALPHA);
                float scale = (MAX_VIS > 0.0) ? (a / MAX_VIS) : 0.0;
                if (scale < 0.0) scale = 0.0;
                if (scale > 1.0) scale = 1.0;
                faceAlpha = entryAlpha * scale;
            }

            llSetLinkGLTFOverrides(L, f, [
                OVERRIDE_GLTF_BASE_ALPHA, faceAlpha
            ]);
        }
    }
    return TRUE;
}

// --- Fade API ---
integer Debug(string message)
{
    if (!ENABLE_DEBUG) return FALSE;
    if (message == "") return FALSE;
    llOwnerSay("[interface] " + message);
    return TRUE;
}

integer StartFade(integer dir) // 1=in, -1=out
{
    if (dir != 1 && dir != -1) return FALSE;

    gDir  = dir;
    gProg = 0.0;

    set_all_mode(MODE_BLEND);

    if (has_texture_config())
    {
        apply_blank_textures();
    }

    if (gDir == 1)
    {
        Debug("FadeIn requested");
        gDieAfterFade = FALSE;
    }
    else
    {
        Debug("FadeOut requested (die after: " + (string)gDieAfterFade + ")");
    }

    if (gDir == 1)      { gATarget = MIN_VIS; gALive = gATarget; }
    else /* gDir == -1 */{ gATarget = MAX_VIS; gALive = gATarget; }

    set_all_alpha(gALive);
    llSetTimerEvent(STEP_TIME);
    return TRUE;
}

integer FadeIn()  { return StartFade(1);  }
integer FadeOut() { return StartFade(-1); }

// --- Messaging ---
integer listen_for_channel(integer channel)
{
    if (gListen) llListenRemove(gListen);
    if (channel == 0) return 0;
    return llListen(channel, "", NULL_KEY, "");
}

integer process_payload(string message)
{
    if (FILTER_BY_NAME)
    {
        string targetName = llJsonGetValue(message, ["NAME"]);
        if (targetName != JSON_INVALID && targetName != gMyName)
        {
            Debug("Ignoring command for different NAME '" + targetName + "'");
            return FALSE;
        }
    }

    string cmd = llJsonGetValue(message, ["COMMAND"]);
    if (cmd == JSON_INVALID)
    {
        Debug("Message missing COMMAND: " + message);
        return FALSE;
    }

    if (llToLower(cmd) == "start")
    {
        Debug("Processing START command");
        FadeIn();
        return TRUE;
    }
    else if (llToLower(cmd) == "stop")
    {
        Debug("Processing STOP command");
        gDieAfterFade = TRUE;
        FadeOut();
        return TRUE;
    }

    Debug("Unknown COMMAND '" + cmd + "'");
    return FALSE;
}

default
{
    state_entry()
    {
        gMyName = llGetObjectName();
        set_all_mode(MODE_BLEND);

        gDir = 0; gProg = 0.0;
        llSetTimerEvent(0.0);

        gChannel = llGetStartParameter();
        gListen = listen_for_channel(gChannel);
        start_texture_config_load();

        // Fade in immediately when rezzed
        FadeIn();
        Debug("State entry complete (channel " + (string)gChannel + ")");
    }

    on_rez(integer param)
    {
        gChannel = param;
        gListen = listen_for_channel(gChannel);
        start_texture_config_load();
        FadeIn();
        Debug("on_rez: channel=" + (string)gChannel);
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            gChannel = llGetStartParameter();
            gListen = listen_for_channel(gChannel);
            start_texture_config_load();
        }
        if (change & CHANGED_INVENTORY)
        {
            start_texture_config_load();
        }
    }

    listen(integer channel, string name, key id, string message)
    {
        if (channel != gChannel) return;
        process_payload(message);
    }

    link_message(integer sender, integer num, string message, key id)
    {
        process_payload(message);
    }

    timer()
    {
        if (gDir != 1 && gDir != -1) { llSetTimerEvent(0.0); return; }

        float T;
        if (gDir == 1)
        {
            T = FADE_IN_TIME;
        }
        else
        {
            T = FADE_OUT_TIME;
        }

        gProg += STEP_TIME / T;
        if (gProg > 1.0) gProg = 1.0;

        float e = ease5(gProg);
        if (gDir == 1)
            gATarget = MIN_VIS + (MAX_VIS - MIN_VIS) * e;
        else
            gATarget = MIN_VIS + (MAX_VIS - MIN_VIS) * (1.0 - e);

        float next = gALive + SMOOTH_FACTOR * (gATarget - gALive);

        if (llFabs(next - gALive) >= WRITE_EPS)
        {
            gALive = next;
            set_all_alpha(gALive);
        }

        if (gProg >= 1.0)
        {
            integer finishedDir = gDir;
            if (gDir == 1)
            {
                gALive = MAX_VIS;
            }
            else
            {
                gALive = MIN_VIS;
            }
            set_all_alpha(gALive);

            gDir = 0;
            llSetTimerEvent(0.0);
            string fadeDir;
            if (finishedDir == 1)
            {
                fadeDir = "in";
                set_all_mode(MODE_OPAQUE);
                if (has_texture_config())
                {
                    apply_final_textures();
                    apply_config_modes();
                }
            }
            else
            {
                fadeDir = "out";
            }

            Debug("Fade " + fadeDir + " complete (dieAfter=" + (string)gDieAfterFade + ")");

            if (finishedDir == -1 && gDieAfterFade)
            {
                Debug("Calling llDie() after fade out");
                llDie();
            }
        }
    }

    dataserver(key request, string data)
    {
        if (request != gTextureRequest)
        {
            return;
        }

        if (data == NOTE_NOT_FOUND)
        {
            Debug("Texture configuration notecard '" + TEXTURE_CONFIG + "' missing.");
            gTextureLoading = FALSE;
            gTextureRequest = NULL_KEY;
            gTexturesReady = FALSE;
            return;
        }

        if (data == NOTE_NOT_READY || data == NOTE_NAK)
        {
            request_next_texture_line();
            return;
        }

        if (data == NOTE_EOF)
        {
            gTextureLoading = FALSE;
            gTextureRequest = NULL_KEY;
            gTexturesReady = TRUE;
            on_texture_config_ready();
            return;
        }

        if (data != "")
        {
            parse_texture_entry(data);
        }

        ++gTextureLine;
        request_next_texture_line();
    }
}
