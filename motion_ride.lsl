// Global variables
integer CHANNEL_ID = -777;
integer CHANNEL_REZZER = -339189999;
vector START_POS;
rotation START_ROT;
list gKeyframeList = [];
string file_name;
integer file_line_number;
key file_request;
key UUID_AVATAR_0 = NULL_KEY;
key UUID_AVATAR_1 = NULL_KEY;
integer FLAG_SIT = FALSE;
float gTotalPathTime = 0.0;
integer gHasStartData = FALSE;
float PATH_RESET_BUFFER = 0.25; // Extra delay before restarting the path

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

StartReadingNoteCard()
{
    llSetKeyframedMotion([], []);
    llSetTimerEvent(0.0);
    gKeyframeList = [];
    gTotalPathTime = 0.0;
    gHasStartData = FALSE;
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
        llListen(CHANNEL_ID, "", NULL_KEY, "");
        llSitTarget(<0.0, 0.0, 1.0>, ZERO_ROTATION);
        llSetKeyframedMotion([], []);
        llSetLinkPrimitiveParamsFast(LINK_ROOT, [
            PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_CONVEX,
            PRIM_LINK_TARGET, LINK_ALL_CHILDREN,
            PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_NONE
        ]);
        llSetText("Fly Duo", <1,1,1>, 1);
        StartReadingNoteCard();

    }
    
    run_time_permissions(integer perm)
    {
        if (perm & PERMISSION_CONTROL_CAMERA)
        {
            list camera_params = [
                CAMERA_ACTIVE, TRUE,
                CAMERA_BEHINDNESS_ANGLE, PI,
                CAMERA_BEHINDNESS_LAG, 0.1,
                CAMERA_DISTANCE, 3.0,
                CAMERA_FOCUS_LAG, 0.0,
                CAMERA_FOCUS_OFFSET, <0.0, 0.0, 1.0>
            ];

            llSetCameraParams(camera_params);
        }
    }

    changed(integer change)
    {
        if (change & CHANGED_INVENTORY)
        {
            llResetScript();
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
                    StartMotion();
                    return;
                }
                file_line_number++;
            }
        }
    }

    listen(integer channel, string name, key id, string message)
    {
        string str;
        if ((str = llJsonGetValue(message, ["END_PATH"])) != JSON_INVALID)
        {
            StartMotion();
        }
    }

    timer()
    {
        StartMotion();
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        // Stand Up AVSitter
        if (num == 90065)
        {
            integer sitter = (integer)msg;
            if (sitter == 0)
            {
                UUID_AVATAR_0 = NULL_KEY;
            }
            if (sitter == 1)
            {
                UUID_AVATAR_1 = NULL_KEY;
            }

            if (UUID_AVATAR_0 == NULL_KEY && UUID_AVATAR_1 == NULL_KEY)
            {
                llSetText("Fly Duo", <1,1,1>, 1);
            }
            else if (UUID_AVATAR_1 == NULL_KEY)
            {
                llSetText("Waiting for a Flight Partner...", <1,1,1>, 1);
            }
            else
            {
                llSetText("", ZERO_VECTOR, 0.0);
            }

            if (UUID_AVATAR_0 == NULL_KEY && UUID_AVATAR_1 == NULL_KEY)
            {
                if (FLAG_SIT)
                {
                    FLAG_SIT = FALSE;
                }
                else
                {
                    llSleep(1);
                    llDie();
                }
            }
        }

        // Sit AVSitter
        if (num == 90060)
        {
            integer sitter = (integer)msg;
            if (sitter == 0)
            {
                UUID_AVATAR_0 = id;
                FLAG_SIT = TRUE;
                llSetText("Waiting for a Flight Partner...", <1,1,1>, 1);
                llRequestPermissions(UUID_AVATAR_0, PERMISSION_CONTROL_CAMERA);
            }
            if (sitter == 1)
            {
                UUID_AVATAR_1 = id;
                FLAG_SIT = FALSE;
                llSetText("", ZERO_VECTOR, 0.0);
                llRegionSay(CHANNEL_REZZER, "NEW");
            }
      }
    }

}
