// Global variables
vector START_POS;
rotation START_ROT;
list gKeyframeList = [];
string file_name;
integer file_line_number;
key file_request;
float gTotalPathTime = 0.0;
integer gHasStartData = FALSE;
float PATH_RESET_BUFFER = 0.25; // Extra delay before restarting the path
float PRE_RIDE_SPEED = 5.0;
float PRE_RIDE_MIN_TIME = 1.0;
float POSITION_EPSILON = 0.01;
float ROTATION_EPSILON = 0.01;
integer gPreRideActive = FALSE;
integer FLAG_WAIT_SITTER = TRUE;
integer gWaitingForSitter = FALSE;

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
    return rot;
}
list parseLine(string line)
{
    integer startIndex = llSubStringIndex(line, "<");
    integer endIndex = llSubStringIndex(line, ">");
    vector pos = (vector)llGetSubString(line, startIndex, endIndex);

    line = llDeleteSubString(line, 0, endIndex);
    startIndex = llSubStringIndex(line, "<");
    endIndex = llSubStringIndex(line, ">");
    rotation rot = (rotation)llGetSubString(line, startIndex, endIndex);
    
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

    llSetKeyframedMotion([], []);
    llSetRegionPos(START_POS);
    llSetRot(START_ROT);
}

StartMotion()
{
    if (!gHasStartData || !llGetListLength(gKeyframeList))
    {
        return;
    }

    gPreRideActive = FALSE;
    gWaitingForSitter = FALSE;
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
    if (gPreRideActive)
    {
        return;
    }

    if (!gHasStartData || !llGetListLength(gKeyframeList))
    {
        StartMotion();
        return;
    }

    gWaitingForSitter = FALSE;
    vector currentPos = llGetPos();
    rotation currentRot = llGetRot();
    vector worldOffset = START_POS - currentPos;
    float distance = llVecMag(worldOffset);
    rotation deltaRot = START_ROT / currentRot;
    float angle = llAngleBetween(currentRot, START_ROT);

    if (distance <= POSITION_EPSILON && angle <= ROTATION_EPSILON)
    {
        StartMotion();
        return;
    }

    vector localOffset = worldOffset / currentRot;
    float duration = 0.0;
    if (distance > 0.0)
    {
        duration = distance / PRE_RIDE_SPEED;
    }
    if (duration < PRE_RIDE_MIN_TIME)
    {
        duration = PRE_RIDE_MIN_TIME;
    }

    llSetKeyframedMotion([], []);
    llSetTimerEvent(0.0);
    gPreRideActive = TRUE;
    llSetKeyframedMotion([localOffset, deltaRot, duration], [KFM_MODE, KFM_FORWARD]);
    llSetTimerEvent(duration + PATH_RESET_BUFFER);
}

StartReadingNoteCard()
{
    llSetKeyframedMotion([], []);
    llSetTimerEvent(0.0);
    gKeyframeList = [];
    gTotalPathTime = 0.0;
    gHasStartData = FALSE;
    gWaitingForSitter = FLAG_WAIT_SITTER;
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
        llSitTarget(<0.0, 0.0, 1.0>, ZERO_ROTATION);
        llSetKeyframedMotion([], []);
        llSetLinkPrimitiveParamsFast(LINK_ROOT, [
            PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_CONVEX,
            PRIM_LINK_TARGET, LINK_ALL_CHILDREN,
            PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_NONE
        ]);
        llSetText("Fly Duo", <1,1,1>, 1);
        key avatar = llAvatarOnSitTarget();
        if (avatar != NULL_KEY)
        {
            llSetText("", ZERO_VECTOR, 0.0);
        }
        gWaitingForSitter = FLAG_WAIT_SITTER;
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
                    if (FLAG_WAIT_SITTER)
                    {
                        key avatar = llAvatarOnSitTarget();
                        if (avatar != NULL_KEY)
                        {
                            StartPreRide();
                        }
                    }
                    else
                    {
                        StartMotion();
                    }
                    return;
                }
                file_line_number++;
            }
        }
    }

    timer()
    {
        if (FLAG_WAIT_SITTER && llAvatarOnSitTarget() == NULL_KEY)
        {
            if (!gWaitingForSitter)
            {
                ResetToStart();
            }
            gWaitingForSitter = TRUE;
            llSetTimerEvent(0.0);
            return;
        }
        StartMotion();
    }

    link_message(integer sender, integer num, string msg, key id)
    {
        if (num == 90060)
        {
            integer sitter = GetSitterNumber(msg);
            if (sitter == 0)
            {
                if (FLAG_WAIT_SITTER && (!gHasStartData || !llGetListLength(gKeyframeList)))
                {
                    gWaitingForSitter = TRUE;
                    return;
                }
                StartPreRide();
            }
        }
    }

}
