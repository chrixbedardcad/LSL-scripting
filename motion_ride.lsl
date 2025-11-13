// Global variables
integer AUTO_RIDE = FALSE;
vector START_POS;
rotation START_ROT;
list gKeyframeList = [];
string file_name;
integer file_line_number;
key file_request;
float gTotalPathTime = 0.0;
integer gHasStartData = FALSE;
float PATH_RESET_BUFFER = 0.25; // Extra delay before restarting the path
vector PRE_RIDE_OFFSET = <10.0, 0.0, 0.0>;
float PRE_RIDE_DURATION = 20.0;
float POSITION_EPSILON = 0.01;
float ROTATION_EPSILON = 0.01;
integer gPreRideActive = FALSE;
integer FLAG_WAIT_SITTER = TRUE;
integer gWaitingForSitter = FALSE;
integer REZZER_CHANNEL = -339189999;
string DEBUG_PREFIX = "[motion_ride debug] ";
integer DEBUG = TRUE;
integer gTrackedSitterCount = 0;
integer gHadAnySitters = FALSE;
list gSitterIds = [];
integer gRezzerNotified = FALSE;

DebugSay(string message)
{
    if (!DEBUG)
    {
        return;
    }

    llOwnerSay(DEBUG_PREFIX + message);
}

integer IsAutoRideMode()
{
    return AUTO_RIDE != FALSE;
}

NotifyRezzerOfNewSitter()
{
    if (!FLAG_WAIT_SITTER || IsAutoRideMode())
    {
        return;
    }

    if (gRezzerNotified)
    {
        return;
    }

    gRezzerNotified = TRUE;
    llRegionSay(REZZER_CHANNEL, "NEW");
}

rotation NormalizeRotation(rotation rot)
{
    float magnitude = llSqrt(rot.x * rot.x + rot.y * rot.y + rot.z * rot.z + rot.s * rot.s);
    if (magnitude <= 0.0)
    {
        return ZERO_ROTATION;
    }

    if (llFabs(1.0 - magnitude) <= 0.00001)
    {
        return rot;
    }

    float invMag = 1.0 / magnitude;
    return <rot.x * invMag, rot.y * invMag, rot.z * invMag, rot.s * invMag>;
}

DumpKeyframeInfo(string context)
{
    integer count = llGetListLength(gKeyframeList) / 3;
    integer index;
    string lines = "";
    for (index = 0; index < count && index < 10; ++index)
    {
        integer base = index * 3;
        vector pos = llList2Vector(gKeyframeList, base);
        rotation rot = llList2Rot(gKeyframeList, base + 1);
        float time = llList2Float(gKeyframeList, base + 2);
        lines += "[#" + (string)index + "] pos=" + (string)pos + " rot=" + (string)rot + " dt=" + (string)time + "\n";
    }
    if (count > 10)
    {
        lines += "... (" + (string)(count - 10) + " additional frames)";
    }
    DebugSay("Keyframe dump (" + context + "): frames=" + (string)count +
        " totalTime=" + (string)gTotalPathTime + "\n" + lines);
}

ReportCurrentTransform(string context)
{
    vector pos = llGetPos();
    rotation rot = llGetRot();
    DebugSay(context + " currentPos=" + (string)pos + " currentRot=" + (string)rot);
}

LogSitterInfo(string context)
{
    integer linkCount = llGetNumberOfPrims();
    integer link;
    list names = [];
    for (link = 1; link <= linkCount; ++link)
    {
        key avatar = llAvatarOnLinkSitTarget(link);
        if (avatar != NULL_KEY)
        {
            names += llKey2Name(avatar);
        }
    }
    integer sitterCount = llGetListLength(names);
    DebugSay("Sitters (" + context + "): count=" + (string)sitterCount + " names=" + llList2CSV(names));
}

integer IsSitterManagementEnabled()
{
    return !IsAutoRideMode() && FLAG_WAIT_SITTER != FALSE;
}

UpdateWaitingForSitter()
{
    if (!IsSitterManagementEnabled())
    {
        gWaitingForSitter = FALSE;
        return;
    }

    if (FLAG_WAIT_SITTER && llAvatarOnSitTarget() == NULL_KEY)
    {
        gWaitingForSitter = TRUE;
        LogSitterInfo("waiting");
        DebugSay("Waiting for sitter (no avatar on sit target).");
    }
    else
    {
        gWaitingForSitter = FALSE;
        LogSitterInfo("ready");
        DebugSay("Not waiting for sitter (avatar present or waiting disabled).");
    }
}

list CollectSitterIds()
{
    if (!IsSitterManagementEnabled())
    {
        return [];
    }

    integer linkCount = llGetNumberOfPrims();
    integer link;
    list sitterIds = [];
    for (link = 1; link <= linkCount; ++link)
    {
        key avatar = llAvatarOnLinkSitTarget(link);
        if (avatar != NULL_KEY)
        {
            if (llListFindList(sitterIds, [avatar]) == -1)
            {
                sitterIds += [avatar];
            }
        }
    }
    return sitterIds;
}

MaybeHandleAllSittersLeft(string context)
{
    if (!IsSitterManagementEnabled())
    {
        return;
    }

    if (gHadAnySitters && gTrackedSitterCount == 0)
    {
        DebugSay("All sitters have left (" + context + "). Deleting ride.");
        llDie();
    }
}

UpdateTrackedSitterCount(integer newCount, string context)
{
    if (!IsSitterManagementEnabled())
    {
        return;
    }

    integer hadAnySittersBefore = gHadAnySitters;
    gTrackedSitterCount = newCount;
    if (newCount > 0)
    {
        if (!hadAnySittersBefore)
        {
            NotifyRezzerOfNewSitter();
        }
        gHadAnySitters = TRUE;
    }
    MaybeHandleAllSittersLeft(context);
}

RefreshSitterCountFromLinks(string context)
{
    if (!IsSitterManagementEnabled())
    {
        return;
    }

    list sitterIds = CollectSitterIds();
    gSitterIds = sitterIds;
    UpdateTrackedSitterCount(llGetListLength(sitterIds), context);
}

TrackSitterJoined(key sitterId, string context)
{
    if (!IsSitterManagementEnabled())
    {
        return;
    }

    if (sitterId == NULL_KEY)
    {
        RefreshSitterCountFromLinks(context + " fallback");
        return;
    }

    if (llListFindList(gSitterIds, [sitterId]) == -1)
    {
        gSitterIds += [sitterId];
    }

    UpdateTrackedSitterCount(llGetListLength(gSitterIds), context);
}

TrackSitterLeft(key sitterId, string context)
{
    if (!IsSitterManagementEnabled())
    {
        return;
    }

    if (sitterId == NULL_KEY)
    {
        RefreshSitterCountFromLinks(context + " fallback");
        return;
    }

    integer index = llListFindList(gSitterIds, [sitterId]);
    if (index != -1)
    {
        gSitterIds = llDeleteSubList(gSitterIds, index, index);
    }

    UpdateTrackedSitterCount(llGetListLength(gSitterIds), context);
}

integer GetSitterNumber(string msg)
{
    list tokens = llParseString2List(msg, [" ", "|", ":", ","], []);
    integer count = llGetListLength(tokens);
    integer index = 0;
    while (index < count)
    {
        string token = llStringTrim(llList2String(tokens, index), STRING_TRIM);
        if (llToLower(token) == "sitter" && (index + 1) < count)
        {
            string nextToken = llList2String(tokens, index + 1);
            return (integer)nextToken;
        }
        if (token != "")
        {
            integer value = (integer)token;
            if ((string)value == token)
            {
                return value;
            }
        }
        index++;
    }
    return -1;
}

list ParseSitterIdsFromSegment(string sitterSegment)
{
    list allSitters = llParseStringKeepNulls(sitterSegment, ["@"], []);
    integer length = llGetListLength(allSitters);
    integer index;
    list sitterIds = [];
    for (index = 0; index < length; ++index)
    {
        string sitterIdStr = llList2String(allSitters, index);
        if (sitterIdStr != "")
        {
            key sitterId = (key)sitterIdStr;
            if (sitterId != NULL_KEY && llListFindList(sitterIds, [sitterId]) == -1)
            {
                sitterIds += [sitterId];
            }
        }
    }
    return sitterIds;
}

integer ParseActiveSitterCount(string msg)
{
    list data = llParseStringKeepNulls(msg, ["|"], []);
    if (llGetListLength(data) < 5)
    {
        return -1;
    }

    list sitterIds = ParseSitterIdsFromSegment(llList2String(data, 4));
    return llGetListLength(sitterIds);
}

list ParseActiveSitterIds(string msg)
{
    list data = llParseStringKeepNulls(msg, ["|"], []);
    if (llGetListLength(data) < 5)
    {
        return [];
    }

    return ParseSitterIdsFromSegment(llList2String(data, 4));
}

vector parseStartPos(string line)
{
    integer startIndex = llSubStringIndex(line, "<");
    integer endIndex = llSubStringIndex(line, ">");
    vector pos = (vector)llGetSubString(line, startIndex, endIndex);
    return pos;
}

rotation parseStartRot(string line)
{
    integer startIndex = llSubStringIndex(line, "<");
    integer endIndex = llSubStringIndex(line, ">");
    line = llDeleteSubString(line, 0, endIndex);
    startIndex = llSubStringIndex(line, "<");
    endIndex = llSubStringIndex(line, ">");
    rotation rot = (rotation)llGetSubString(line, startIndex, endIndex);
    return NormalizeRotation(rot);
}
list parseLine(string line)
{
    integer startIndex = llSubStringIndex(line, "<");
    integer endIndex = llSubStringIndex(line, ">");
    vector pos = (vector)llGetSubString(line, startIndex, endIndex);

    line = llDeleteSubString(line, 0, endIndex);
    startIndex = llSubStringIndex(line, "<");
    endIndex = llSubStringIndex(line, ">");
    rotation rot = NormalizeRotation((rotation)llGetSubString(line, startIndex, endIndex));
    
    string durationText = llStringTrim(llDeleteSubString(line, 0, endIndex), STRING_TRIM);
    float time = (float)durationText;
    return [pos, rot, time];
}

ResetToStart()
{
    if (!gHasStartData)
    {
        return;
    }

    llSetKeyframedMotion([], [KFM_COMMAND, KFM_CMD_STOP]);
    llSetKeyframedMotion([], []);
    llSetRegionPos(START_POS);
    llSetRot(START_ROT);
}

StartMotion()
{
    if (!gHasStartData || !llGetListLength(gKeyframeList))
    {
        DebugSay("StartMotion aborted: missing start data or empty keyframe list.");
        return;
    }

    gPreRideActive = FALSE;
    gWaitingForSitter = FALSE;
    DebugSay("Starting motion. Timer set for " + (string)(gTotalPathTime + PATH_RESET_BUFFER) + " seconds.");
    DumpKeyframeInfo("StartMotion");
    ReportCurrentTransform("StartMotion before reset");
    ResetToStart();
    llSetKeyframedMotion(gKeyframeList, [KFM_MODE, KFM_FORWARD]);

    if (gTotalPathTime > 0.0)
    {
        llSetTimerEvent(gTotalPathTime + PATH_RESET_BUFFER);
    }
    else
    {
        llSetTimerEvent(0.0);
    }
}

StartPreRide()
{
    if (IsAutoRideMode())
    {
        StartMotion();
        return;
    }

    if (gPreRideActive)
    {
        DebugSay("StartPreRide ignored: pre-ride already active.");
        return;
    }

    if (!gHasStartData || !llGetListLength(gKeyframeList))
    {
        DebugSay("StartPreRide fallback: missing data so starting motion directly.");
        StartMotion();
        return;
    }

    gWaitingForSitter = FALSE;
    DebugSay("StartPreRide invoked. Executing simple forward motion.");
    llSetKeyframedMotion([], [KFM_COMMAND, KFM_CMD_STOP]);
    llSetKeyframedMotion([], []);
    llSetTimerEvent(0.0);
    gPreRideActive = TRUE;
    llSetKeyframedMotion([
        PRE_RIDE_OFFSET,
        ZERO_ROTATION,
        PRE_RIDE_DURATION
    ], [
        KFM_MODE, KFM_FORWARD
    ]);
    llSetTimerEvent(PRE_RIDE_DURATION);
}

StartReadingNoteCard()
{
    llSetKeyframedMotion([], [KFM_COMMAND, KFM_CMD_STOP]);
    llSetKeyframedMotion([], []);
    llSetTimerEvent(0.0);
    gKeyframeList = [];
    gTotalPathTime = 0.0;
    gHasStartData = FALSE;
    UpdateWaitingForSitter();
    file_name = llGetInventoryName(INVENTORY_NOTECARD, 0);
    if (file_name == "")
    {
        llOwnerSay("No path notecard found in inventory.");
        return;
    }
    file_line_number = 0;
    file_request = llGetNotecardLine(file_name, file_line_number);
}

default {
    state_entry()
    {
        llSetKeyframedMotion([], []);
        llSetLinkPrimitiveParamsFast(LINK_ROOT, [
            PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_CONVEX,
            PRIM_LINK_TARGET, LINK_ALL_CHILDREN,
            PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_NONE
        ]);
        if (IsAutoRideMode())
        {
            llSetText("", ZERO_VECTOR, 0.0);
            gWaitingForSitter = FALSE;
        }
        else
        {
            llSitTarget(<0.0, 0.0, 1.0>, ZERO_ROTATION);
            llSetText("Fly Duo", <1,1,1>, 1);
            key avatar = llAvatarOnSitTarget();
            if (avatar != NULL_KEY)
            {
                llSetText("", ZERO_VECTOR, 0.0);
            }
            RefreshSitterCountFromLinks("state_entry");
            UpdateWaitingForSitter();
        }
        StartReadingNoteCard();

    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & CHANGED_INVENTORY)
        {
            llResetScript();
        }

        if (IsAutoRideMode())
        {
            return;
        }

        if (change & CHANGED_LINK)
        {
            key avatar = llAvatarOnSitTarget();
            if (avatar != NULL_KEY)
            {
                llSetText("", ZERO_VECTOR, 0.0);
            }
            else
            {
                llSetText("Fly Duo", <1,1,1>, 1);
            }
            RefreshSitterCountFromLinks("changed");
            if (avatar == NULL_KEY)
            {
                MaybeHandleAllSittersLeft("changed post-stand");
            }
        }
    }
    
    dataserver(key query_id, string data)
    {
        if (query_id == file_request)
        {
            while (data != EOF && data != NAK)
            {
                data = llGetNotecardLineSync(file_name, file_line_number);
                if (file_line_number == 0)
                {
                    START_ROT = parseStartRot(data);
                    START_POS = parseStartPos(data);
                    gHasStartData = TRUE;
                }
                else if (data == NAK)
                {
                    llOwnerSay("Warning: NAK reading file: " + file_name + " line: " + (string)file_line_number);
                    file_request = llGetNotecardLine(file_name, file_line_number);
                }
                else if (data != EOF)
                {
                    list keyframe = parseLine(data);
                    if (llGetListLength(keyframe) == 3)
                    {
                        gKeyframeList += keyframe;
                        gTotalPathTime += llList2Float(keyframe, 2);
                    }
                }
                else
                {
                    llOwnerSay("Reading " + file_name + " done " + (string)file_line_number + " lines.");
                    DumpKeyframeInfo("load");
                    if (IsAutoRideMode())
                    {
                        StartMotion();
                        return;
                    }
                    key avatar = llAvatarOnSitTarget();
                    if (avatar != NULL_KEY)
                    {
                        gWaitingForSitter = FALSE;
                        StartPreRide();
                    }
                    else
                    {
                        UpdateWaitingForSitter();
                        if (!gWaitingForSitter)
                        {
                            StartMotion();
                        }
                    }
                    return;
                }
                file_line_number++;
            }
        }
    }

    timer()
    {
        if (IsAutoRideMode())
        {
            StartMotion();
            return;
        }

        if (gPreRideActive)
        {
            DebugSay("Pre-ride motion complete. Preparing to start main motion.");
            llSetKeyframedMotion([], [KFM_COMMAND, KFM_CMD_STOP]);
            llSetKeyframedMotion([], []);
            gPreRideActive = FALSE;
            llSetTimerEvent(0.0);
            if (gHasStartData)
            {
                llSetRegionPos(START_POS);
                llSetRot(START_ROT);
            }
            StartMotion();
            return;
        }
        if (!IsSitterManagementEnabled())
        {
            DebugSay("Timer fired with sitter management disabled. Continuing motion without sitter checks.");
        }
        else if (FLAG_WAIT_SITTER && llAvatarOnSitTarget() == NULL_KEY)
        {
            if (!gWaitingForSitter)
            {
                DebugSay("Timer fired with no sitter. Resetting to start.");
                ResetToStart();
            }
            gWaitingForSitter = TRUE;
            llSetTimerEvent(0.0);
            return;
        }
        DebugSay("Timer fired. Starting motion.");
        ReportCurrentTransform("Timer start");
        StartMotion();
    }

    link_message(integer sender, integer num, string msg, key id)
    {
        if (IsAutoRideMode())
        {
            return;
        }

        if (num == 90060)
        {
            TrackSitterJoined(id, "link_message 90060");
            integer sitter = GetSitterNumber(msg);
            if (sitter == 0)
            {
                if (FLAG_WAIT_SITTER && (!gHasStartData || !llGetListLength(gKeyframeList)))
                {
                    gWaitingForSitter = TRUE;
                    return;
                }
                LogSitterInfo("link_message");
                StartPreRide();
            }
        }
        else if (num == 90045)
        {
            integer activeSitters = ParseActiveSitterCount(msg);
            if (activeSitters >= 0)
            {
                list sitterIds = ParseActiveSitterIds(msg);
                gSitterIds = sitterIds;
                UpdateTrackedSitterCount(activeSitters, "link_message 90045");
            }
        }
        else if (num == 90065)
        {
            TrackSitterLeft(id, "link_message 90065");
        }
    }

}
