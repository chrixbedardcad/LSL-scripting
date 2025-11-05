// motion.lsl -- Plays staged keyframed motions loaded from three path files.
//
// Stage 1 (Fade In):  Plays path.fadeIN forward once, then transitions to Stage 2.
// Stage 2 (Run Loop): Plays path.run in ping-pong mode until a Stop command arrives.
// Stage 3 (Fade Out): Plays path.fadeOUT forward once, then calls llDie() when done.
//
// The script expects three notecards (or inventory files) named:
//   path.fadeIN, path.run, path.fadeOUT
// Each line must follow the format:
//   [comment] <x, y, z><qx, qy, qz, qw>seconds
// The comment section is optional and ignored. Positions are parsed as vectors and
// rotations as quaternions. The trailing value specifies the seconds to reach the
// keyframe.

// --- Configuration ------------------------------------------------------------
string PATH_FADEIN  = "path.fadeIN";
string PATH_RUN     = "path.run";
string PATH_FADEOUT = "path.fadeOUT";

float  TIMER_MARGIN = 0.2; // Extra seconds added to timers to ensure completion.

// --- Loader state ------------------------------------------------------------
integer PATH_ID_FADEIN  = 0;
integer PATH_ID_RUN     = 1;
integer PATH_ID_FADEOUT = 2;

integer gLoadPhase = -1;
integer gLoadLine  = 0;
key     gLoadQuery = NULL_KEY;

list gKeyframesFadeIn  = [];
list gKeyframesRun     = [];
list gKeyframesFadeOut = [];

float gDurationFadeIn  = 0.0;
float gDurationRun     = 0.0;
float gDurationFadeOut = 0.0;

integer gPathsReady = FALSE;
integer gLoadError = FALSE;
integer gStartQueued = TRUE; // Auto-start after loading by default.

integer gDebugEnabled = TRUE; // Enable verbose debugging output.

// Notecard constants
string NOTE_EOF       = EOF;
string NOTE_NOT_FOUND = "NOT_FOUND";
string NOTE_NOT_READY = "NOT_READY";
string NOTE_NAK       = NAK;

// --- Stage state -------------------------------------------------------------
integer STAGE_IDLE    = 0;
integer STAGE_FADEIN  = 1;
integer STAGE_RUN     = 2;
integer STAGE_FADEOUT = 3;

integer gStage = STAGE_IDLE;
float   gStageTimer = 0.0;
integer gStopRequested = FALSE;

// --- Helpers -----------------------------------------------------------------
string path_name(integer phase)
{
    if (phase == PATH_ID_FADEIN)  return PATH_FADEIN;
    if (phase == PATH_ID_RUN)     return PATH_RUN;
    if (phase == PATH_ID_FADEOUT) return PATH_FADEOUT;
    return "";
}

float path_duration(integer phase)
{
    if (phase == PATH_ID_FADEIN)  return gDurationFadeIn;
    if (phase == PATH_ID_RUN)     return gDurationRun;
    if (phase == PATH_ID_FADEOUT) return gDurationFadeOut;
    return 0.0;
}

list parse_keyframe_line(string raw)
{
    string line = llStringTrim(raw, STRING_TRIM);
    if (line == "")
    {
        return [];
    }

    string firstTwo = llToLower(llGetSubString(line, 0, 1));
    string firstOne = llToLower(llGetSubString(line, 0, 0));
    if (llGetSubString(line, 0, 1) == "//" || firstTwo == "--" || firstOne == "#")
    {
        return [];
    }

    integer first = llSubStringIndex(line, "<");
    if (first < 0)
    {
        return [];
    }

    string working = llGetSubString(line, first, -1);

    integer posClose = llSubStringIndex(working, ">");
    if (posClose < 0)
    {
        return [];
    }

    string posSegment = llGetSubString(working, 1, posClose - 1);
    string afterPos = llStringTrim(llGetSubString(working, posClose + 1, -1), STRING_TRIM);

    integer rotOpen = llSubStringIndex(afterPos, "<");
    if (rotOpen < 0)
    {
        return [];
    }

    integer rotClose = llSubStringIndex(afterPos, ">");
    if (rotClose < 0)
    {
        return [];
    }

    string rotSegment = llGetSubString(afterPos, rotOpen + 1, rotClose - 1);
    string afterRot = llStringTrim(llGetSubString(afterPos, rotClose + 1, -1), STRING_TRIM);

    if (afterRot == "")
    {
        return [];
    }

    list posParts = llCSV2List(posSegment);
    list rotParts = llCSV2List(rotSegment);

    if (llGetListLength(posParts) < 3 || llGetListLength(rotParts) < 4)
    {
        return [];
    }

    float px = (float)llStringTrim(llList2String(posParts, 0), STRING_TRIM);
    float py = (float)llStringTrim(llList2String(posParts, 1), STRING_TRIM);
    float pz = (float)llStringTrim(llList2String(posParts, 2), STRING_TRIM);

    float qx = (float)llStringTrim(llList2String(rotParts, 0), STRING_TRIM);
    float qy = (float)llStringTrim(llList2String(rotParts, 1), STRING_TRIM);
    float qz = (float)llStringTrim(llList2String(rotParts, 2), STRING_TRIM);
    float qw = (float)llStringTrim(llList2String(rotParts, 3), STRING_TRIM);

    float duration = (float)afterRot;

    vector   position = <px, py, pz>;
    rotation rotationQ = <qx, qy, qz, qw>;

    if (gDebugEnabled)
    {
        llOwnerSay("motion.lsl: parsed frame "
            + "pos=" + (string)position
            + " rot=" + (string)rotationQ
            + " dur=" + (string)duration);
    }

    return [position, rotationQ, duration];
}

integer append_keyframe(integer phase, list frame)
{
    if (llGetListLength(frame) < 3)
    {
        return FALSE;
    }

    float duration = llList2Float(frame, 2);

    if (phase == PATH_ID_FADEIN)
    {
        gKeyframesFadeIn += frame;
        gDurationFadeIn += duration;
    }
    else if (phase == PATH_ID_RUN)
    {
        gKeyframesRun += frame;
        gDurationRun += duration;
    }
    else if (phase == PATH_ID_FADEOUT)
    {
        gKeyframesFadeOut += frame;
        gDurationFadeOut += duration;
    }
    else
    {
        return FALSE;
    }

    if (gDebugEnabled)
    {
        integer framesIn = llGetListLength(gKeyframesFadeIn) / 3;
        integer framesRun = llGetListLength(gKeyframesRun) / 3;
        integer framesOut = llGetListLength(gKeyframesFadeOut) / 3;
        llOwnerSay("motion.lsl: appended frame to phase " + (string)phase
            + " (counts fadeIn/run/fadeOut="
            + (string)framesIn + "/"
            + (string)framesRun + "/"
            + (string)framesOut + ")");
    }

    return TRUE;
}

integer request_notecard_line()
{
    string card = path_name(gLoadPhase);
    if (card == "")
    {
        return FALSE;
    }

    integer invType = llGetInventoryType(card);
    if (invType != INVENTORY_NOTECARD)
    {
        llOwnerSay("motion.lsl: Unable to find notecard '" + card + "'.");
        gLoadError = TRUE;
        return FALSE;
    }

    gLoadQuery = llGetNotecardLine(card, gLoadLine);
    if (gLoadQuery == NULL_KEY)
    {
        llOwnerSay("motion.lsl: Failed to request line " + (string)gLoadLine + " of '" + card + "'.");
        gLoadError = TRUE;
        return FALSE;
    }

    return TRUE;
}

integer begin_path_load(integer phase)
{
    gLoadPhase = phase;
    gLoadLine = 0;
    return request_notecard_line();
}

integer reset_paths()
{
    gKeyframesFadeIn  = [];
    gKeyframesRun     = [];
    gKeyframesFadeOut = [];

    gDurationFadeIn  = 0.0;
    gDurationRun     = 0.0;
    gDurationFadeOut = 0.0;

    return TRUE;
}

integer stop_motion()
{
    if (gDebugEnabled)
    {
        llOwnerSay("motion.lsl: stop_motion()");
    }
    llSetKeyframedMotion([], [KFM_CMD_STOP]);

    return TRUE;
}

integer schedule_timer(float seconds)
{
    gStageTimer = seconds;
    if (seconds <= 0.0)
    {
        llSetTimerEvent(0.0);
        return TRUE;
    }
    llSetTimerEvent(seconds + TIMER_MARGIN);

    return TRUE;
}

list build_kfm_list(list frames)
{
    list kfm = [];
    integer len = llGetListLength(frames);
    integer idx = 0;

    while (idx + 2 < len)
    {
        vector   pos = llList2Vector(frames, idx);
        rotation rot = llList2Rot(frames, idx + 1);
        float    dur = llList2Float(frames, idx + 2);

        kfm += [pos, dur, rot, dur];
        idx += 3;
    }

    if (idx < len && gDebugEnabled)
    {
        llOwnerSay("motion.lsl: WARNING leftover data when building keyframes -> "
            + llList2CSV(llList2List(frames, idx, -1)));
    }

    return kfm;
}

integer play_keyframes(list frames, integer mode)
{
    integer frameLen = llGetListLength(frames);
    if (frameLen < 3)
    {
        if (gDebugEnabled)
        {
            llOwnerSay("motion.lsl: play_keyframes aborting, list too short (" + (string)llGetListLength(frames) + ")");
        }
        return FALSE;
    }

    stop_motion();
    integer remainder = frameLen % 3;
    list kfmFrames = build_kfm_list(frames);
    integer kfmLen = llGetListLength(kfmFrames);
    if (gDebugEnabled)
    {
        llOwnerSay("motion.lsl: play_keyframes length=" + (string)frameLen
            + " remainder=" + (string)remainder
            + " mode=" + (string)mode
            + " kfmLength=" + (string)kfmLen);
        if (remainder != 0)
        {
            llOwnerSay("motion.lsl: WARNING frame list not multiple of 3 -> " + llList2CSV(frames));
        }
    }

    if (kfmLen < 2)
    {
        if (gDebugEnabled)
        {
            llOwnerSay("motion.lsl: play_keyframes aborting, converted list too short (" + (string)kfmLen + ")");
        }
        return FALSE;
    }

    llSetKeyframedMotion(kfmFrames, [
        KFM_MODE, mode,
        KFM_DATA, KFM_TRANSLATION | KFM_ROTATION
    ]);
    return TRUE;
}

integer start_stage(integer stage)
{
    if (!gPathsReady)
    {
        if (gDebugEnabled)
        {
            llOwnerSay("motion.lsl: start_stage(" + (string)stage + ") aborted, paths not ready");
        }
        return FALSE;
    }

    if (stage == STAGE_FADEIN)
    {
        if (!play_keyframes(gKeyframesFadeIn, KFM_FORWARD))
        {
            return FALSE;
        }
        gStage = STAGE_FADEIN;
        gStopRequested = FALSE;
        if (gDebugEnabled)
        {
            llOwnerSay("motion.lsl: starting STAGE_FADEIN");
        }
        schedule_timer(path_duration(PATH_ID_FADEIN));
        return TRUE;
    }
    else if (stage == STAGE_RUN)
    {
        if (!play_keyframes(gKeyframesRun, KFM_PING_PONG))
        {
            return FALSE;
        }
        gStage = STAGE_RUN;
        if (gDebugEnabled)
        {
            llOwnerSay("motion.lsl: starting STAGE_RUN");
        }
        schedule_timer(0.0);
        return TRUE;
    }
    else if (stage == STAGE_FADEOUT)
    {
        if (!play_keyframes(gKeyframesFadeOut, KFM_FORWARD))
        {
            return FALSE;
        }
        gStage = STAGE_FADEOUT;
        if (gDebugEnabled)
        {
            llOwnerSay("motion.lsl: starting STAGE_FADEOUT");
        }
        schedule_timer(path_duration(PATH_ID_FADEOUT));
        return TRUE;
    }

    return FALSE;
}

integer attempt_start_sequence()
{
    if (!gStartQueued)
    {
        return FALSE;
    }

    if (!gPathsReady || gStage != STAGE_IDLE)
    {
        return FALSE;
    }

    if (start_stage(STAGE_FADEIN))
    {
        gStartQueued = FALSE;
        return TRUE;
    }

    return FALSE;
}

integer handle_stop_command()
{
    gStopRequested = TRUE;

    if (!gPathsReady)
    {
        return FALSE;
    }

    if (gStage == STAGE_RUN)
    {
        start_stage(STAGE_FADEOUT);
    }
    else if (gStage == STAGE_FADEIN)
    {
        start_stage(STAGE_FADEOUT);
    }
    else if (gStage == STAGE_IDLE)
    {
        start_stage(STAGE_FADEOUT);
    }

    return TRUE;
}

integer reset_and_load()
{
    stop_motion();
    schedule_timer(0.0);
    gStage = STAGE_IDLE;
    gStopRequested = FALSE;
    gPathsReady = FALSE;
    gLoadError = FALSE;
    gLoadQuery = NULL_KEY;
    gStartQueued = TRUE;

    reset_paths();

    if (!begin_path_load(PATH_ID_FADEIN))
    {
        gLoadError = TRUE;
    }

    return TRUE;
}

integer handle_message(string message)
{
    string cmd = llToLower(llStringTrim(message, STRING_TRIM));
    if (cmd == "start")
    {
        gStartQueued = TRUE;
        attempt_start_sequence();
        return TRUE;
    }
    else if (cmd == "stop")
    {
        handle_stop_command();
        return TRUE;
    }

    return FALSE;
}

// --- Events ------------------------------------------------------------------

default
{
    state_entry()
    {
        reset_and_load();
    }

    on_rez(integer start_param)
    {
        reset_and_load();
    }

    changed(integer change)
    {
        if (change & (CHANGED_INVENTORY | CHANGED_OWNER))
        {
            reset_and_load();
        }
    }

    dataserver(key query_id, string data)
    {
        if (query_id != gLoadQuery)
        {
            return;
        }

        if (data == NOTE_NOT_READY || data == NOTE_NAK)
        {
            request_notecard_line();
            return;
        }

        if (data == NOTE_NOT_FOUND)
        {
            llOwnerSay("motion.lsl: Notecard '" + path_name(gLoadPhase) + "' not found.");
            gLoadError = TRUE;
            return;
        }

        if (data == NOTE_EOF)
        {
            if (gLoadPhase == PATH_ID_FADEIN)
            {
                begin_path_load(PATH_ID_RUN);
                return;
            }
            else if (gLoadPhase == PATH_ID_RUN)
            {
                begin_path_load(PATH_ID_FADEOUT);
                return;
            }
            else if (gLoadPhase == PATH_ID_FADEOUT)
            {
                gPathsReady = !gLoadError;
                gLoadQuery = NULL_KEY;
                attempt_start_sequence();
                return;
            }
        }

        list frame = parse_keyframe_line(data);
        if (llGetListLength(frame) >= 3)
        {
            append_keyframe(gLoadPhase, frame);
        }

        gLoadLine += 1;
        request_notecard_line();
    }

    link_message(integer sender, integer num, string str, key id)
    {
        if (str != "")
        {
            if (handle_message(str))
            {
                return;
            }
        }

        if (id != NULL_KEY)
        {
            handle_message((string)id);
        }
    }

    timer()
    {
        schedule_timer(0.0);

        if (gStage == STAGE_FADEIN)
        {
            if (gStopRequested)
            {
                start_stage(STAGE_FADEOUT);
            }
            else
            {
                start_stage(STAGE_RUN);
            }
        }
        else if (gStage == STAGE_FADEOUT)
        {
            llDie();
        }
    }
}
