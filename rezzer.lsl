// rezzer.lsl -- Listens for JSON rez commands and rezzes objects accordingly

integer CHANNEL = -987654; // Must match the channel used by caller.lsl
vector  BASE_OFFSET = <0.0, 0.0, 1.0>; // Offset from rezzer position for the first object
vector  OFFSET_STEP = <0.0, 0.0, 0.75>; // Step offset applied per object rezzed

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

integer process_payload(string message)
{
    string command = llJsonGetValue(message, ["COMMAND"]);
    if (command == JSON_INVALID)
    {
        return FALSE;
    }

    if (llToLower(command) != "rez")
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
        process_payload(message);
    }
}
