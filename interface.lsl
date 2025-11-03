// Receiver: Fade In / Out controlled by JSON over llRegionSay
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
integer MODE_BLEND = PRIM_GLTF_ALPHA_MODE_BLEND;

// ---- State ----
integer gListen = 0;
integer gDir = 0;      // 1=in, -1=out, 0=idle
float   gProg = 0.0;
float   gATarget = 0.0;
float   gALive   = 0.0;
string  gMyName;
integer gChannel = 0;
integer gDieAfterFade = FALSE;

// Quintic easing 0..1 -> 0..1
float ease5(float t) { return t*t*t * (t*(6.0*t - 15.0) + 10.0); }

// --- Helpers ---
integer set_all_mode_blend_once()
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
                OVERRIDE_GLTF_BASE_ALPHA_MODE, MODE_BLEND
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
            llSetLinkGLTFOverrides(L, f, [
                OVERRIDE_GLTF_BASE_ALPHA, a
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
        set_all_mode_blend_once();

        gDir = 0; gProg = 0.0;
        llSetTimerEvent(0.0);

        gChannel = llGetStartParameter();
        gListen = listen_for_channel(gChannel);

        // Fade in immediately when rezzed
        FadeIn();
        Debug("State entry complete (channel " + (string)gChannel + ")");
    }

    on_rez(integer param)
    {
        gChannel = param;
        gListen = listen_for_channel(gChannel);
        FadeIn();
        Debug("on_rez: channel=" + (string)gChannel);
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            gChannel = llGetStartParameter();
            gListen = listen_for_channel(gChannel);
        }
    }

    listen(integer channel, string name, key id, string message)
    {
        if (channel != gChannel) return;
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
}
