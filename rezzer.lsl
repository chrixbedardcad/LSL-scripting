// rezzer.lsl -- Listens for JSON rez commands and rezzes objects accordingly

integer CHANNEL = -987654; // Must match the channel used by caller.lsl
vector  BASE_OFFSET = <0.0, 0.0, 1.0>; // Offset from rezzer position for the first object
vector  OFFSET_STEP = <0.0, 0.0, 0.75>; // Step offset applied per object rezzed

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

string build_move_rez_ack(integer seq, string objectName, integer success)
{
    string status = success ? "ok" : "fail";

    return llList2Json(JSON_OBJECT,
        [
            "COMMAND",     "move_rez_complete",
            "SEQ",         (string)seq,
            "OBJECT_NAME", objectName,
            "STATUS",      status
        ]);
}

// --- Helpers ----------------------------------------------------------------

integer validate_inventory(string objectName)
{
    if (llGetInventoryType(objectName) == INVENTORY_OBJECT)
    {
        return TRUE;
    }

    llOwnerSay("rezzer.lsl: Object '" + objectName + "' is missing from inventory.");
    return FALSE;
}

integer rez_object(string objectName, integer count)
{
    if (!validate_inventory(objectName))
    {
        return FALSE;
    }

    vector basePos = llGetPos() + BASE_OFFSET;
    rotation rezRot = llGetRot();

    integer i;
    for (i = 0; i < count; ++i)
    {
        vector rezPos = basePos + (OFFSET_STEP * (float)i);
        // Pass the shared channel as the start parameter so the rezzed
        // interface scripts know which channel to listen on for start/stop
        // commands. Without this the interface never receives the "stop"
        // message and therefore never triggers FadeOut/llDie().
        llRezObject(objectName, rezPos, ZERO_VECTOR, rezRot, CHANNEL);
    }

    return TRUE;
}

integer perform_move_rez(string objectName, vector targetPos, vector rotEuler)
{
    if (!validate_inventory(objectName))
    {
        return FALSE;
    }

    if (!llSetRegionPos(targetPos))
    {
        llOwnerSay("rezzer.lsl: Unable to move to position " + (string)targetPos + ".");
        return FALSE;
    }

    rotation rezRot = llEuler2Rot(rotEuler * DEG_TO_RAD);
    llSetRot(rezRot);

    vector rezPos = llGetPos();
    llRezObject(objectName, rezPos, ZERO_VECTOR, rezRot, CHANNEL);

    return TRUE;
}

integer process_payload(string message)
{
    string command = llJsonGetValue(message, ["COMMAND"]);
    if (command == JSON_INVALID)
    {
        return FALSE;
    }

    string lowerCommand = llToLower(command);

    if (lowerCommand == "move_rez")
    {
        string objectName = llJsonGetValue(message, ["OBJECT_NAME"]);
        string posStr = llJsonGetValue(message, ["POS"]);
        string rotStr = llJsonGetValue(message, ["ROT"]);
        integer seq = (integer)llJsonGetValue(message, ["SEQ"]);

        integer success = TRUE;

        if (objectName == JSON_INVALID || objectName == "")
        {
            llOwnerSay("rezzer.lsl: Missing OBJECT_NAME in message: " + message);
            success = FALSE;
        }

        if (posStr == JSON_INVALID || posStr == "")
        {
            llOwnerSay("rezzer.lsl: Missing POS in message: " + message);
            success = FALSE;
        }

        if (rotStr == JSON_INVALID || rotStr == "")
        {
            llOwnerSay("rezzer.lsl: Missing ROT in message: " + message);
            success = FALSE;
        }

        vector targetPos;
        vector rotEuler;

        if (success)
        {
            string posFormatted = ensure_vector_format(posStr);
            string rotFormatted = ensure_vector_format(rotStr);

            if (posFormatted == "" || rotFormatted == "")
            {
                success = FALSE;
            }
            else
            {
                targetPos = (vector)posFormatted;
                rotEuler = (vector)rotFormatted;
            }
        }

        if (success)
        {
            success = perform_move_rez(objectName, targetPos, rotEuler);
        }

        llRegionSay(CHANNEL, build_move_rez_ack(seq, objectName, success));
        return success;
    }

    if (lowerCommand != "rez")
    {
        return FALSE;
    }

    string objectName = llJsonGetValue(message, ["OBJECT_NAME"]);
    integer qty = (integer)llJsonGetValue(message, ["QTY"]);

    if (objectName == JSON_INVALID || objectName == "")
    {
        llOwnerSay("rezzer.lsl: Missing OBJECT_NAME in message: " + message);
        return FALSE;
    }

    if (qty <= 0)
    {
        qty = 1;
    }

    rez_object(objectName, qty);
    return TRUE;
}

// --- Events -----------------------------------------------------------------

default
{
    state_entry()
    {
        llListen(CHANNEL, "", NULL_KEY, "");
    }

    on_rez(integer param)
    {
        llResetScript();
    }

    listen(integer channel, string name, key id, string message)
    {
        if (id == llGetKey())
        {
            return;
        }

        process_payload(message);
    }
}
