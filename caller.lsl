// caller.lsl -- Reads rez.cfg and sends rez commands to rezzer via llRegionSay
// Assumes rez.cfg is a notecard or script file in the object's inventory with
// one JSON object per line describing the object name and quantity.

integer CHANNEL = -987654;           // Channel used to communicate with rezzer.lsl
string  CONFIG_NOTECARD = "rez.cfg"; // Name of the configuration notecard/file
string  POS_NOTECARD    = "pos.json"; // Name of the position configuration file

// llGetNotecardLineSync returns literal strings when encountering specific conditions.
// Define them explicitly so the compiler recognizes the names.
string  NOTE_EOF        = EOF;          // End-of-file marker
string  NOTE_NOT_FOUND  = "NOT_FOUND"; // Notecard missing from inventory
string  NOTE_NOT_READY  = "NOT_READY"; // Asset data not yet available
string  NOTE_NAK        = NAK;           // Dataserver indicates to retry asynchronously

list gEntries;           // Stores each configuration line as a JSON string
list gPositions;         // Stores position/rotation pairs (vector, vector)
list gAvailablePositionIndices; // Tracks remaining indices for randomized selection
integer gEntriesReady;   // TRUE when rez.cfg is loaded
integer gPositionsReady; // TRUE when pos.json is loaded
integer gReady = FALSE;  // TRUE when configuration is fully loaded
string  gPayloadTemplate;
integer gLoadLine;       // Current line number requested from the notecard
key     gLoadRequest;    // Handle for the outstanding notecard request
integer gLoading;        // TRUE while a notecard request is pending
string  gCurrentNotecard;// Currently loading notecard name
integer gLoadPhase;      // Which notecard is being loaded

integer gListenerHandle; // Listen handle for acknowledgement messages

integer gSequenceActive;    // TRUE while a rez sequence is active
integer gSequenceIdCounter; // Rolling sequence id counter
integer gActiveSequenceId;  // Identifier for the active sequence
string  gSeqObjectName;     // Object being rezzed in the active sequence
integer gSeqQty;            // Total quantity to rez in the active sequence
integer gSeqCompleted;      // Number of items already acknowledged as rezzed
integer gAwaitingAck;       // TRUE while waiting for rezzer acknowledgement
integer gNextPositionIndex = -1; // Last index selected from gPositions
vector  gHomeBasePos;       // Recorded base position for the rezzer
integer gHomePosRecorded;   // TRUE when gHomeBasePos holds a valid value
integer gTimerEnabled;      // TRUE when the automatic rez timer is active
integer gDebugEnabled = TRUE; // Controls whether debug output is emitted

float   TIMER_INTERVAL = 30.0; // Seconds between automatic rez attempts
float   REZ_DELAY      = 0.4;  // Delay between rez attempts for organic dispersion

integer LOAD_PHASE_NONE = 0;
integer LOAD_PHASE_REZ  = 1;
integer LOAD_PHASE_POS  = 2;

string build_payload_template()
{
    return llList2Json(JSON_OBJECT, [
        "COMMAND",    "rez",
        "OBJECT_NAME", "",
        "QTY",         "0"
    ]);
}

integer debug_log(string message)
{
    if (!gDebugEnabled)
    {
        return FALSE;
    }

    llOwnerSay(message);
    return TRUE;
}

// --- Helpers ----------------------------------------------------------------

integer entry_count()
{
    return llGetListLength(gEntries);
}

integer position_count()
{
    return llGetListLength(gPositions) / 2;
}

vector position_at(integer idx)
{
    return llList2Vector(gPositions, idx * 2);
}

vector rotation_at(integer idx)
{
    return llList2Vector(gPositions, (idx * 2) + 1);
}

integer record_home_position()
{
    gHomeBasePos = llGetPos();
    gHomePosRecorded = TRUE;
    return TRUE;
}

integer return_rezzer_home()
{
    vector basePos;

    if (gHomePosRecorded)
    {
        basePos = gHomeBasePos;
    }
    else
    {
        basePos = llGetPos();
        gHomeBasePos = basePos;
        gHomePosRecorded = TRUE;
    }

    vector targetPos = basePos + <0.0, 0.0, 1.0>;

    string payload = llList2Json(JSON_OBJECT,
        [
            "COMMAND", "return_home",
            "POS",     (string)targetPos
        ]);

    llRegionSay(CHANNEL, payload);
    return TRUE;
}

string ensure_vector_format(string raw)
{
    string trimmed = llStringTrim(raw, STRING_TRIM);

    if (trimmed == "")
    {
        return trimmed;
    }

    if (llGetSubString(trimmed, 0, 0) != "<")
    {
        trimmed = "<" + trimmed;
    }

    if (llGetSubString(trimmed, -1, -1) != ">")
    {
        trimmed += ">";
    }

    return trimmed;
}

integer store_position_entry(string jsonLine)
{
    string posStr = llJsonGetValue(jsonLine, ["pos"]);
    string rotStr = llJsonGetValue(jsonLine, ["rot"]);

    if (posStr == JSON_INVALID || rotStr == JSON_INVALID)
    {
        debug_log("caller.lsl: Invalid entry in '" + POS_NOTECARD + "': " + jsonLine);
        return FALSE;
    }

    string posFormatted = ensure_vector_format(posStr);
    string rotFormatted = ensure_vector_format(rotStr);

    if (posFormatted == "" || rotFormatted == "")
    {
        debug_log("caller.lsl: Empty vector value in '" + POS_NOTECARD + "': " + jsonLine);
        return FALSE;
    }

    vector targetPos = (vector)posFormatted;
    vector targetRot = (vector)rotFormatted;

    gPositions += [targetPos, targetRot];
    return TRUE;
}

list build_position_pool()
{
    list pool = [];
    integer total = position_count();

    integer i;
    for (i = 0; i < total; ++i)
    {
        pool += [i];
    }

    return pool;
}

integer take_random_position_index()
{
    integer poolCount = llGetListLength(gAvailablePositionIndices);

    if (poolCount <= 0)
    {
        gAvailablePositionIndices = build_position_pool();
        poolCount = llGetListLength(gAvailablePositionIndices);
    }

    if (poolCount <= 0)
    {
        return -1;
    }

    integer selected;
    integer attempts = 0;
    integer poolIndex;

    do
    {
        poolIndex = (integer)llFrand((float)poolCount);
        selected = llList2Integer(gAvailablePositionIndices, poolIndex);
        ++attempts;
    }
    while (poolCount > 1 && selected == gNextPositionIndex && attempts < 6);

    gAvailablePositionIndices = llDeleteSubList(gAvailablePositionIndices, poolIndex, poolIndex);
    return selected;
}

integer begin_notecard_load(string notecard, integer phase)
{
    gCurrentNotecard = notecard;
    gLoadPhase = phase;
    gLoadLine = 0;
    gLoadRequest = NULL_KEY;
    gLoading = FALSE;

    gLoadRequest = llGetNotecardLine(gCurrentNotecard, gLoadLine);

    if (gLoadRequest == NULL_KEY)
    {
        debug_log("caller.lsl: Failed to request notecard '" + gCurrentNotecard + "'.");
        return FALSE;
    }

    gLoading = TRUE;
    return TRUE;
}

integer start_config_load()
{
    if (!gHomePosRecorded)
    {
        record_home_position();
    }

    gTimerEnabled = FALSE;
    llSetTimerEvent(0.0);
    send_stop_command();
    return_rezzer_home();

    gEntries = [];
    gPositions = [];
    gEntriesReady = FALSE;
    gPositionsReady = FALSE;
    gReady = FALSE;
    gLoading = FALSE;
    gLoadLine = 0;
    gLoadRequest = NULL_KEY;
    gCurrentNotecard = "";
    gLoadPhase = LOAD_PHASE_NONE;
    gSequenceActive = FALSE;
    gAwaitingAck = FALSE;
    gActiveSequenceId = -1;
    gNextPositionIndex = -1;
    gAvailablePositionIndices = [];

    if (gPayloadTemplate == "")
    {
        gPayloadTemplate = build_payload_template();
    }

    if (llGetInventoryType(CONFIG_NOTECARD) != INVENTORY_NOTECARD)
    {
        debug_log("caller.lsl: Unable to find configuration notecard '" + CONFIG_NOTECARD + "'.");
        return FALSE;
    }

    if (llGetInventoryType(POS_NOTECARD) != INVENTORY_NOTECARD)
    {
        debug_log("caller.lsl: Unable to find configuration notecard '" + POS_NOTECARD + "'.");
        return FALSE;
    }

    return begin_notecard_load(CONFIG_NOTECARD, LOAD_PHASE_REZ);
}

integer parse_quantity(string json)
{
    string qtyStr = llJsonGetValue(json, ["QTY"]);
    if (qtyStr == JSON_INVALID) return 0;
    return (integer)qtyStr;
}

string parse_object_name(string json)
{
    return llJsonGetValue(json, ["Object_Name"]);
}

integer send_cmd(integer channelId, string object_name, integer qty)
{
    string payload = gPayloadTemplate;
    payload = llJsonSetValue(payload, ["OBJECT_NAME"], object_name);
    payload = llJsonSetValue(payload, ["QTY"], (string) qty);

    llRegionSay(channelId, payload);
    return TRUE;
}

integer send_stop_command()
{
    string payload = llList2Json(JSON_OBJECT, [
        "COMMAND", "stop"
    ]);

    llRegionSay(CHANNEL, payload);
    return TRUE;
}

integer toggle_rez_timer()
{
    if (!gReady && !gTimerEnabled)
    {
        debug_log("caller.lsl: Configuration not ready; cannot enable timer yet.");
        return FALSE;
    }

    gTimerEnabled = !gTimerEnabled;

    if (gTimerEnabled)
    {
        llSetTimerEvent(TIMER_INTERVAL);
        debug_log("caller.lsl: Automatic rez timer enabled.");

        if (!gSequenceActive && !gAwaitingAck)
        {
            if (!start_random_command())
            {
                debug_log("caller.lsl: Unable to start rez sequence immediately; will retry on timer.");
            }
        }
    }
    else
    {
        llSetTimerEvent(0.0);
        send_stop_command();
        gSequenceActive = FALSE;
        gAwaitingAck = FALSE;
        gActiveSequenceId = -1;
        gSeqObjectName = "";
        gSeqQty = 0;
        gSeqCompleted = 0;
        return_rezzer_home();
        debug_log("caller.lsl: Automatic rez timer disabled and rezzer reset.");
    }

    return TRUE;
}

integer dispatch_next_rez()
{
    if (!gSequenceActive)
    {
        return FALSE;
    }

    if (gSeqCompleted >= gSeqQty)
    {
        debug_log("caller.lsl: Completed rezzing " + (string)gSeqQty + " of '" + gSeqObjectName + "'.");
        gSequenceActive = FALSE;
        gActiveSequenceId = -1;
        return_rezzer_home();
        return TRUE;
    }

    integer totalPositions = position_count();

    if (totalPositions <= 0)
    {
        debug_log("caller.lsl: No positions available in '" + POS_NOTECARD + "'.");
        gSequenceActive = FALSE;
        return FALSE;
    }

    integer index = take_random_position_index();

    if (index < 0)
    {
        debug_log("caller.lsl: Unable to select a rez position.");
        gSequenceActive = FALSE;
        return FALSE;
    }

    vector targetPos = position_at(index);
    vector targetRot = rotation_at(index);

    gNextPositionIndex = index;

    string payload = llList2Json(JSON_OBJECT,
        [
            "COMMAND",     "move_rez",
            "SEQ",         (string)gActiveSequenceId,
            "OBJECT_NAME", gSeqObjectName,
            "POS",         (string)targetPos,
            "ROT",         (string)targetRot
        ]);

    if (REZ_DELAY > 0.0)
    {
        llSleep(REZ_DELAY);
    }

    llRegionSay(CHANNEL, payload);
    gAwaitingAck = TRUE;
    return TRUE;
}

integer start_random_command()
{
    integer count = entry_count();
    if (!gReady || count <= 0)
    {
        return FALSE;
    }

    if (gSequenceActive || gAwaitingAck)
    {
        debug_log("caller.lsl: A rez sequence is already in progress.");
        return FALSE;
    }

    integer index = (integer)llFrand((float)count);
    string jsonLine = llList2String(gEntries, index);

    string objName = parse_object_name(jsonLine);
    integer qty    = parse_quantity(jsonLine);

    if (objName == JSON_INVALID || objName == "")
    {
        debug_log("caller.lsl: Invalid Object_Name in configuration entry #" + (string)(index + 1));
        return FALSE;
    }

    if (qty <= 0)
    {
        qty = 1; // fallback to one rez if missing/invalid
    }

    // Ensure any previously rezzed objects are instructed to clean up before starting
    // a new sequence run.
    send_stop_command();

    gSequenceActive = TRUE;
    gSeqObjectName = objName;
    gSeqQty = qty;
    gSeqCompleted = 0;
    gAwaitingAck = FALSE;
    gActiveSequenceId = ++gSequenceIdCounter;
    gAvailablePositionIndices = build_position_pool();

    if (gActiveSequenceId <= 0)
    {
        gActiveSequenceId = 1;
        gSequenceIdCounter = gActiveSequenceId;
    }

    if (!dispatch_next_rez())
    {
        gSequenceActive = FALSE;
        gActiveSequenceId = -1;
        return FALSE;
    }

    return TRUE;
}

// --- Events -----------------------------------------------------------------

default
{
    state_entry()
    {
        record_home_position();

        if (gListenerHandle)
        {
            llListenRemove(gListenerHandle);
        }

        gListenerHandle = llListen(CHANNEL, "", NULL_KEY, "");
        start_config_load();
    }

    on_rez(integer param)
    {
        record_home_position();

        if (gListenerHandle)
        {
            llListenRemove(gListenerHandle);
        }

        gListenerHandle = llListen(CHANNEL, "", NULL_KEY, "");
        start_config_load();
    }

    touch_start(integer total_number)
    {
        if (!gReady)
        {
            debug_log("caller.lsl: Configuration not ready yet.");
            return;
        }

        toggle_rez_timer();
    }

    changed(integer change)
    {
        if (change & (CHANGED_INVENTORY | CHANGED_OWNER))
        {
            start_config_load();
        }
    }

    timer()
    {
        if (!gTimerEnabled)
        {
            llSetTimerEvent(0.0);
            return;
        }

        if (!gReady)
        {
            debug_log("caller.lsl: Configuration lost; disabling timer.");
            gTimerEnabled = FALSE;
            llSetTimerEvent(0.0);
            return;
        }

        if (gSequenceActive || gAwaitingAck)
        {
            return;
        }

        if (!start_random_command())
        {
            debug_log("caller.lsl: Timer failed to start rez sequence; will retry.");
        }
    }

    listen(integer channel, string name, key id, string message)
    {
        if (channel != CHANNEL)
        {
            return;
        }

        if (id == llGetKey())
        {
            return;
        }

        string command = llJsonGetValue(message, ["COMMAND"]);

        if (command == JSON_INVALID)
        {
            return;
        }

        if (llToLower(command) != "move_rez_complete")
        {
            return;
        }

        integer seq = (integer)llJsonGetValue(message, ["SEQ"]);

        if (!gSequenceActive || !gAwaitingAck || seq != gActiveSequenceId)
        {
            return;
        }

        gAwaitingAck = FALSE;

        string status = llToLower(llJsonGetValue(message, ["STATUS"]));
        if (status == JSON_INVALID || status == "")
        {
            status = "ok";
        }

        if (status != "ok")
        {
            gSequenceActive = FALSE;
            gActiveSequenceId = -1;
            debug_log("caller.lsl: Rezzer reported failure for '" + gSeqObjectName + "'.");
            return_rezzer_home();
            return;
        }

        ++gSeqCompleted;
        dispatch_next_rez();
    }

    dataserver(key request_id, string data)
    {
        if (!gLoading || request_id != gLoadRequest)
        {
            return;
        }

        string message = data;

        while (message != NOTE_EOF && message != NOTE_NAK && message != NOTE_NOT_FOUND && message != NOTE_NOT_READY)
        {
            string trimmed = llStringTrim(message, STRING_TRIM);
            if (trimmed != "")
            {
                if (gLoadPhase == LOAD_PHASE_REZ)
                {
                    gEntries += [trimmed];
                }
                else if (gLoadPhase == LOAD_PHASE_POS)
                {
                    store_position_entry(trimmed);
                }
            }

            ++gLoadLine;
            message = llGetNotecardLineSync(gCurrentNotecard, gLoadLine);
        }

        if (message == NOTE_NAK || message == NOTE_NOT_READY)
        {
            gLoadRequest = llGetNotecardLine(gCurrentNotecard, gLoadLine);
            return;
        }

        gLoading = FALSE;

        if (message == NOTE_EOF)
        {
            if (gLoadPhase == LOAD_PHASE_REZ)
            {
                gEntriesReady = TRUE;
                debug_log("caller.lsl: Loaded " + (string)entry_count() + " configuration entries.");

                if (!begin_notecard_load(POS_NOTECARD, LOAD_PHASE_POS))
                {
                    return;
                }

                return;
            }

            if (gLoadPhase == LOAD_PHASE_POS)
            {
                gPositionsReady = TRUE;
                debug_log("caller.lsl: Loaded " + (string)position_count() + " positions.");

                gReady = (gEntriesReady && gPositionsReady);

                if (gReady)
                {
                    debug_log("caller.lsl: Ready to rez objects.");
                }

                return;
            }

            return;
        }

        if (message == NOTE_NOT_FOUND)
        {
            debug_log("caller.lsl: Unable to read notecard '" + gCurrentNotecard + "'.");
            return;
        }

        debug_log("caller.lsl: Unexpected response while reading notecard '" + gCurrentNotecard + "'.");
    }
}
